Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Normalize-AidosRepositoryHandoffPublicUrl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ServerUrl)

    $value=$ServerUrl.Trim()
    $uri=$null
    if(-not[Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri)){throw 'Repository handoff public URL must be an absolute HTTPS URL.'}
    if(-not[string]::Equals($uri.Scheme,'https',[StringComparison]::OrdinalIgnoreCase)){throw 'Repository handoff public URL must use HTTPS.'}
    if(-not[string]::IsNullOrWhiteSpace($uri.UserInfo)){throw 'Repository handoff public URL may not contain user information.'}
    if(-not[string]::IsNullOrWhiteSpace($uri.Query) -or -not[string]::IsNullOrWhiteSpace($uri.Fragment)){throw 'Repository handoff public URL may not contain a query or fragment.'}
    if([string]::IsNullOrWhiteSpace($uri.Host)){throw 'Repository handoff public URL must contain a host.'}
    $path=$uri.AbsolutePath.TrimEnd('/')
    $builder=[UriBuilder]::new($uri)
    $builder.Path=if([string]::IsNullOrWhiteSpace($path)){''}else{$path}
    $builder.Query=''
    $builder.Fragment=''
    $builder.Uri.AbsoluteUri.TrimEnd('/')
}

function New-AidosRepositoryHandoffOpenApiDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ServerUrl)

    $server=Normalize-AidosRepositoryHandoffPublicUrl -ServerUrl $ServerUrl
    $nullableString=[ordered]@{type='string';nullable=$true}
    $nullableInteger=[ordered]@{type='integer';nullable=$true;minimum=1}
    $errorResponse=[ordered]@{
        description='The request was rejected.'
        content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/ErrorResponse'}}}
    }

    [ordered]@{
        openapi='3.0.3'
        info=[ordered]@{
            title='AIDOS Repository Handoff Gateway'
            version='0.2.0'
            description='Private AIDOS Thinker and Human Input transport. Read exact Core-published authority, use only authorized sources, submit bound Thinker results, and surface/submit exact Human Input without moving lifecycle authority into ChatGPT.'
        }
        servers=@([ordered]@{url=$server;description='AIDOS private Tailscale Funnel endpoint'})
        security=@([ordered]@{BearerAuth=@()})
        paths=[ordered]@{
            '/v1/projects/{projectId}/handoff'=[ordered]@{
                get=[ordered]@{
                    operationId='getAidosProjectHandoff'
                    summary='Read the current AIDOS handoff for one exact project'
                    description='Use only the project_id supplied by the AIDOS_HANDOFF_READY trigger. Verify handoff_id and handoff_sha256 against that trigger before doing any work.'
                    'x-openai-isConsequential'=$false
                    parameters=@([ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id from the trigger.';schema=[ordered]@{type='string';minLength=1}})
                    responses=[ordered]@{
                        '200'=[ordered]@{description='Current handoff, exact payload and human-readable instructions.';content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/HandoffResponse'}}}}
                        '401'=$errorResponse
                        '409'=$errorResponse
                    }
                }
            }
            '/v1/projects/{projectId}/human-input'=[ordered]@{
                get=[ordered]@{
                    operationId='getAidosHumanInput'
                    summary='Read the current WAITING Human Input Request for one exact project'
                    description='Use the exact project_id from an AIDOS_HUMAN_INPUT_REQUIRED trigger or from the most recent unresolved AIDOS Human Input presentation. The response is authoritative; never rely on chat history for request content.'
                    'x-openai-isConsequential'=$false
                    parameters=@([ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id.';schema=[ordered]@{type='string';minLength=1}})
                    responses=[ordered]@{
                        '200'=[ordered]@{description='Current WAITING Human Input Request, or NO_HUMAN_INPUT.';content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/HumanInputResponse'}}}}
                        '401'=$errorResponse
                        '409'=$errorResponse
                    }
                }
            }
            '/v1/projects/{projectId}/human-input/{requestId}/response'=[ordered]@{
                post=[ordered]@{
                    operationId='submitAidosHumanInputResponse'
                    summary='Submit the operator response to one exact AIDOS Human Input Request'
                    description='Call only after the user has clearly answered the currently fetched request. Copy project_id, request_id and request_sha256 exactly. AIDOS Core validates request binding and permitted options, persists the response/resume intent, and selects the next lifecycle step.'
                    'x-openai-isConsequential'=$false
                    parameters=@(
                        [ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id.';schema=[ordered]@{type='string';minLength=1}},
                        [ordered]@{name='requestId';in='path';required=$true;description='Exact request_id returned by getAidosHumanInput.';schema=[ordered]@{type='string';format='uuid'}}
                    )
                    requestBody=[ordered]@{required=$true;content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/HumanInputSubmitRequest'}}}}
                    responses=[ordered]@{
                        '200'=[ordered]@{description='Human Input response accepted or already accepted idempotently.';content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/HumanInputAcceptedResponse'}}}}
                        '401'=$errorResponse
                        '409'=$errorResponse
                    }
                }
            }
            '/v1/projects/{projectId}/sources'=[ordered]@{
                get=[ordered]@{
                    operationId='getAidosAuthorizedSource'
                    summary='Read one source authorized by the current assignment handoff'
                    description='Call only for exact source_refs returned by getAidosProjectHandoff. Do not construct or broaden paths.'
                    'x-openai-isConsequential'=$false
                    parameters=@(
                        [ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id from the trigger.';schema=[ordered]@{type='string';minLength=1}},
                        [ordered]@{name='path';in='query';required=$true;description='Exact project-relative source_ref returned by the current handoff.';schema=[ordered]@{type='string';minLength=1}}
                    )
                    responses=[ordered]@{
                        '200'=[ordered]@{description='Exact UTF-8 source content with its SHA-256.';content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/SourceResponse'}}}}
                        '401'=$errorResponse
                        '409'=$errorResponse
                    }
                }
            }
            '/v1/projects/{projectId}/results'=[ordered]@{
                post=[ordered]@{
                    operationId='submitAidosBoundResult'
                    summary='Submit one exact Thinker result to AIDOS Core'
                    description='Submit only the result envelope required by the current handoff. Copy every binding and identity field exactly. expected_parent_handoff_id must equal the current assignment handoff_id. AIDOS Core validates the result and selects the next actor.'
                    'x-openai-isConsequential'=$false
                    parameters=@([ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id from the trigger.';schema=[ordered]@{type='string';minLength=1}})
                    requestBody=[ordered]@{required=$true;content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/SubmitResultRequest'}}}}
                    responses=[ordered]@{
                        '200'=[ordered]@{description='Result accepted or already accepted idempotently.';content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/AcceptedResultResponse'}}}}
                        '401'=$errorResponse
                        '409'=$errorResponse
                    }
                }
            }
        }
        components=[ordered]@{
            securitySchemes=[ordered]@{
                BearerAuth=[ordered]@{type='http';scheme='bearer';bearerFormat='AIDOS-API-Key';description='Use the 256-bit API key generated by the AIDOS repository handoff installer.'}
            }
            schemas=[ordered]@{
                Binding=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('project_state','definition_id','definition_version','execution_id','revision','review_id')
                    properties=[ordered]@{
                        project_state=$nullableString
                        definition_id=$nullableString
                        definition_version=$nullableInteger
                        execution_id=$nullableString
                        revision=$nullableInteger
                        review_id=$nullableString
                    }
                }
                HandoffMetadata=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('schema_version','envelope_type','handoff_id','project_id','kind','from_actor','to_actor','status','parent_handoff_id','created_at','action','payload_ref','payload_sha256','binding','source_refs')
                    properties=[ordered]@{
                        schema_version=[ordered]@{type='string';enum=@('0.1')}
                        envelope_type=[ordered]@{type='string';enum=@('AIDOS_REPOSITORY_HANDOFF')}
                        handoff_id=[ordered]@{type='string';format='uuid'}
                        project_id=[ordered]@{type='string';minLength=1}
                        kind=[ordered]@{type='string';enum=@('ASSIGNMENT','RESULT')}
                        from_actor=[ordered]@{type='string';enum=@('CORE','THINKER','WORKER','HUMAN')}
                        to_actor=[ordered]@{type='string';enum=@('CORE','THINKER','WORKER','HUMAN')}
                        status=[ordered]@{type='string';enum=@('READY')}
                        parent_handoff_id=[ordered]@{type='string';format='uuid';nullable=$true}
                        created_at=[ordered]@{type='string';format='date-time'}
                        action=[ordered]@{type='string';minLength=1}
                        payload_ref=[ordered]@{type='string';minLength=1}
                        payload_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$';nullable=$true}
                        binding=[ordered]@{'$ref'='#/components/schemas/Binding'}
                        source_refs=[ordered]@{type='array';items=[ordered]@{type='string';minLength=1};uniqueItems=$true}
                    }
                }
                Payload=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('path','sha256','content')
                    properties=[ordered]@{
                        path=[ordered]@{type='string';minLength=1}
                        sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        content=[ordered]@{oneOf=@([ordered]@{type='object';additionalProperties=$true},[ordered]@{type='string'})}
                    }
                }
                HandoffResponse=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('status','project_id','handoff_sha256','metadata','body','payload')
                    properties=[ordered]@{
                        status=[ordered]@{type='string';enum=@('READY')}
                        project_id=[ordered]@{type='string';minLength=1}
                        handoff_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        metadata=[ordered]@{'$ref'='#/components/schemas/HandoffMetadata'}
                        body=[ordered]@{type='string'}
                        payload=[ordered]@{'$ref'='#/components/schemas/Payload'}
                    }
                }
                HumanInputOption=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('option_id','label','description')
                    properties=[ordered]@{
                        option_id=[ordered]@{type='string';minLength=1}
                        label=[ordered]@{type='string';minLength=1}
                        description=$nullableString
                    }
                }
                HumanInputResponse=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('status','project_id')
                    properties=[ordered]@{
                        status=[ordered]@{type='string';enum=@('READY','NO_HUMAN_INPUT')}
                        project_id=[ordered]@{type='string';minLength=1}
                        request_id=[ordered]@{type='string';format='uuid';nullable=$true}
                        request_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$';nullable=$true}
                        phase=$nullableString
                        request_type=$nullableString
                        context_summary=$nullableString
                        question=$nullableString
                        options=[ordered]@{type='array';items=[ordered]@{'$ref'='#/components/schemas/HumanInputOption'}}
                        authority_classification=$nullableString
                        auto_define_stop_reason=$nullableString
                        binding=[ordered]@{'$ref'='#/components/schemas/Binding'}
                    }
                }
                HumanInputSubmitRequest=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('request_sha256')
                    properties=[ordered]@{
                        request_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        selected_option_id=$nullableString
                        text=$nullableString
                    }
                }
                HumanInputAcceptedResponse=[ordered]@{
                    type='object'
                    additionalProperties=$true
                    required=@('status','project_id','request_id')
                    properties=[ordered]@{
                        status=[ordered]@{type='string';enum=@('ACCEPTED','ALREADY_ACCEPTED')}
                        project_id=[ordered]@{type='string';minLength=1}
                        request_id=[ordered]@{type='string';format='uuid'}
                        resume_ref=$nullableString
                    }
                }
                SourceResponse=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('project_id','source_ref','sha256','byte_length','content')
                    properties=[ordered]@{
                        project_id=[ordered]@{type='string';minLength=1}
                        source_ref=[ordered]@{type='string';minLength=1}
                        sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        byte_length=[ordered]@{type='integer';minimum=0}
                        content=[ordered]@{type='string'}
                    }
                }
                RuntimeActorResult=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('schema_version','envelope_type','assignment_id','assignment_sha256','project_id','actor_role','actor_identity','action','binding','outcome','result','responded_at')
                    properties=[ordered]@{
                        schema_version=[ordered]@{type='string';enum=@('0.1')}
                        envelope_type=[ordered]@{type='string';enum=@('RUNTIME_ACTOR_RESULT')}
                        assignment_id=[ordered]@{type='string';format='uuid'}
                        assignment_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        project_id=[ordered]@{type='string';minLength=1}
                        actor_role=[ordered]@{type='string';enum=@('THINKER')}
                        actor_identity=[ordered]@{type='string';minLength=1}
                        action=[ordered]@{type='string';minLength=1}
                        binding=[ordered]@{'$ref'='#/components/schemas/Binding'}
                        outcome=[ordered]@{type='string';enum=@('COMPLETED','BLOCKED','FAILED')}
                        result=[ordered]@{type='object';additionalProperties=$true}
                        responded_at=[ordered]@{type='string';format='date-time'}
                    }
                }
                EvidenceRef=[ordered]@{
                    type='object'
                    additionalProperties=$true
                    required=@('path','sha256')
                    properties=[ordered]@{
                        path=[ordered]@{type='string';minLength=1}
                        sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                    }
                }
                ReviewResponse=[ordered]@{
                    type='object'
                    additionalProperties=$true
                    required=@('schema_version','envelope_type','review_id','project_id','definition_id','definition_version','execution_id','revision','assignment_sha256','package_manifest_sha256','outcome','reason','evidence_refs','repair_guidance','responded_at','responded_by')
                    properties=[ordered]@{
                        schema_version=[ordered]@{type='string';enum=@('0.1')}
                        envelope_type=[ordered]@{type='string';enum=@('REVIEW_RESPONSE')}
                        review_id=[ordered]@{type='string';format='uuid'}
                        project_id=[ordered]@{type='string';minLength=1}
                        definition_id=[ordered]@{type='string';minLength=1}
                        definition_version=[ordered]@{type='integer';minimum=1}
                        execution_id=[ordered]@{type='string';minLength=1}
                        revision=[ordered]@{type='integer';minimum=1}
                        assignment_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        package_manifest_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        outcome=[ordered]@{type='string';minLength=1}
                        reason=[ordered]@{type='string';minLength=1}
                        evidence_refs=[ordered]@{type='array';minItems=1;items=[ordered]@{'$ref'='#/components/schemas/EvidenceRef'}}
                        repair_guidance=[ordered]@{type='array';items=[ordered]@{type='string'}}
                        responded_at=[ordered]@{type='string';format='date-time'}
                        responded_by=[ordered]@{type='string';minLength=1}
                    }
                }
                SubmitResultRequest=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('expected_parent_handoff_id','result')
                    properties=[ordered]@{
                        expected_parent_handoff_id=[ordered]@{type='string';format='uuid'}
                        summary=[ordered]@{type='string';nullable=$true}
                        result=[ordered]@{oneOf=@([ordered]@{'$ref'='#/components/schemas/RuntimeActorResult'},[ordered]@{'$ref'='#/components/schemas/ReviewResponse'})}
                    }
                }
                AcceptedResultResponse=[ordered]@{
                    type='object'
                    additionalProperties=$true
                    required=@('status')
                    properties=[ordered]@{status=[ordered]@{type='string';enum=@('ACCEPTED','ALREADY_ACCEPTED')}}
                }
                ErrorResponse=[ordered]@{
                    type='object'
                    additionalProperties=$true
                    required=@('error')
                    properties=[ordered]@{error=[ordered]@{type='string'};detail=[ordered]@{type='string';nullable=$true}}
                }
            }
        }
    }
}

function ConvertTo-AidosRepositoryHandoffOpenApiJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ServerUrl)
    New-AidosRepositoryHandoffOpenApiDocument -ServerUrl $ServerUrl|ConvertTo-Json -Depth 100
}

function Write-AidosRepositoryHandoffOpenApiDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ServerUrl,[Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    $dir=Split-Path -Parent $full
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$full.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        ConvertTo-AidosRepositoryHandoffOpenApiJson -ServerUrl $ServerUrl|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
        Move-Item -LiteralPath $tmp -Destination $full -Force
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
    [pscustomobject][ordered]@{status='WRITTEN';path=$full;server_url=(Normalize-AidosRepositoryHandoffPublicUrl -ServerUrl $ServerUrl)}
}

Export-ModuleMember -Function Normalize-AidosRepositoryHandoffPublicUrl,New-AidosRepositoryHandoffOpenApiDocument,ConvertTo-AidosRepositoryHandoffOpenApiJson,Write-AidosRepositoryHandoffOpenApiDocument
