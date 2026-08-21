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
    $nullableString=[ordered]@{type=@('string','null')}
    $nullableInteger=[ordered]@{type=@('integer','null');minimum=1}
    $errorResponse=[ordered]@{
        description='The request was rejected.'
        content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/ErrorResponse'}}}
    }

    [ordered]@{
        openapi='3.1.0'
        info=[ordered]@{
            title='AIDOS Repository Handoff Gateway'
            version='0.2.0'
            description='Private AIDOS Thinker, Human Input and operator-control transport. ChatGPT carries exact intent only; AIDOS Core retains lifecycle authority.'
        }
        servers=@([ordered]@{url=$server;description='AIDOS private Tailscale Funnel endpoint'})
        security=@([ordered]@{BearerAuth=@()})
        paths=[ordered]@{
            '/v1/projects/{projectId}/control'=[ordered]@{
                post=[ordered]@{
                    operationId='submitAidosChatControl'
                    summary='Submit an exact START or STOP operator intent to AIDOS Core'
                    description='Call only for an exact whole-message chat control recognized by the GPT instructions. START maps to Core RESUME; STOP maps to Core PAUSE at a safe boundary. The gateway fixes requested_by to CHATGPT_OPERATOR, persists the intent, and returns a durable acknowledgement.'
                    'x-openai-isConsequential'=$false
                    parameters=@([ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id encoded in the bound conversation title.';schema=[ordered]@{type='string';minLength=1}})
                    requestBody=[ordered]@{required=$true;content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/ChatControlRequest'}}}}
                    responses=[ordered]@{
                        '200'=[ordered]@{description='Durably accepted, already applied, or rejected control intent.';content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/ChatControlResponse'}}}}
                        '401'=$errorResponse
                        '409'=$errorResponse
                    }
                }
            }
            '/v1/projects/{projectId}/goals'=[ordered]@{
                post=[ordered]@{
                    operationId='submitAidosProjectGoal'
                    summary='Submit one explicit new project goal to AIDOS Core'
                    description='Call only when the entire newest user message begins with the exact AIDOS GOAL: prefix. Submit the remaining text verbatim. Core accepts only an IDLE, RUNNING project with completed Definition lineage, creates a new exact Definition binding, persists and pushes the goal, and then selects the Thinker.'
                    'x-openai-isConsequential'=$false
                    parameters=@([ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id encoded in the bound conversation title.';schema=[ordered]@{type='string';minLength=1}})
                    requestBody=[ordered]@{required=$true;content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/ProjectGoalRequest'}}}}
                    responses=[ordered]@{
                        '200'=[ordered]@{description='Durably accepted new project goal and Definition binding.';content=[ordered]@{'application/json'=[ordered]@{schema=[ordered]@{'$ref'='#/components/schemas/ProjectGoalResponse'}}}}
                        '401'=$errorResponse
                        '409'=$errorResponse
                    }
                }
            }
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
                    description='Call only for exact source_refs returned by getAidosProjectHandoff. Read from startCharacter 0 and follow exact next_start values until complete is true. Do not construct or broaden paths.'
                    'x-openai-isConsequential'=$false
                    parameters=@(
                        [ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id from the trigger.';schema=[ordered]@{type='string';minLength=1}},
                        [ordered]@{name='path';in='query';required=$true;description='Exact project-relative source_ref returned by the current handoff.';schema=[ordered]@{type='string';minLength=1}},
                        [ordered]@{name='startCharacter';in='query';required=$false;description='Exact zero-based UTF-16 continuation offset. Start with 0; thereafter copy next_start exactly.';schema=[ordered]@{type='integer';minimum=0;default=0}},
                        [ordered]@{name='maxCharacters';in='query';required=$false;description='Maximum UTF-16 characters returned in one bounded response.';schema=[ordered]@{type='integer';minimum=1;maximum=65536;default=65536}}
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
                ChatControlRequest=[ordered]@{
                    type='object';additionalProperties=$false;required=@('command')
                    properties=[ordered]@{command=[ordered]@{type='string';enum=@('START','STOP')}}
                }
                ChatControlResponse=[ordered]@{
                    type='object';additionalProperties=$false
                    required=@('status','project_id','command','acknowledgement','control_id','control_mode','reason','intent_ref')
                    properties=[ordered]@{
                        status=[ordered]@{type='string';enum=@('ACCEPTED','ALREADY_APPLIED','REJECTED')}
                        project_id=[ordered]@{type='string';minLength=1}
                        command=[ordered]@{type='string';enum=@('START','STOP')}
                        acknowledgement=[ordered]@{type='string';enum=@('AIDOS_CONTROL_ACCEPTED::START','AIDOS_CONTROL_ACCEPTED::STOP','AIDOS_CONTROL_ALREADY_RUNNING','AIDOS_CONTROL_ALREADY_PAUSED','AIDOS_CONTROL_REJECTED')}
                        control_id=[ordered]@{type='string';format='uuid'}
                        control_mode=[ordered]@{type='string';enum=@('RUNNING','PAUSED','SAFE_STOPPED')}
                        reason=[ordered]@{type=@('string','null')}
                        intent_ref=[ordered]@{type='string';minLength=1}
                    }
                }
                ProjectGoalRequest=[ordered]@{
                    type='object';additionalProperties=$false;required=@('goal')
                    properties=[ordered]@{goal=[ordered]@{type='string';minLength=10;maxLength=12000}}
                }
                ProjectGoalResponse=[ordered]@{
                    type='object';additionalProperties=$false
                    required=@('status','project_id','goal_id','goal_ref','definition_id','definition_version','project_state','acknowledgement')
                    properties=[ordered]@{
                        status=[ordered]@{type='string';enum=@('ACCEPTED')}
                        project_id=[ordered]@{type='string';minLength=1}
                        goal_id=[ordered]@{type='string';pattern='^GOAL-[0-9a-f-]{36}$'}
                        goal_ref=[ordered]@{type='string';minLength=1}
                        definition_id=[ordered]@{type='string';pattern='^DEF-[0-9a-f-]{36}$'}
                        definition_version=[ordered]@{type='integer';const=1}
                        project_state=[ordered]@{type='string';const='WAITING_DEFINITION'}
                        acknowledgement=[ordered]@{type='string';pattern='^AIDOS_GOAL_ACCEPTED::GOAL-[0-9a-f-]{36}$'}
                        persistence=[ordered]@{type='object';additionalProperties=$true}
                        workspace=[ordered]@{type='object';additionalProperties=$true}
                    }
                }
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
                        parent_handoff_id=[ordered]@{type=@('string','null');format='uuid'}
                        created_at=[ordered]@{type='string';format='date-time'}
                        action=[ordered]@{type='string';minLength=1}
                        payload_ref=[ordered]@{type='string';minLength=1}
                        payload_sha256=[ordered]@{type=@('string','null');pattern='^[0-9a-f]{64}$'}
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
                        content=[ordered]@{type='object';additionalProperties=$true}
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
                    required=@('option_id','label')
                    properties=[ordered]@{
                        option_id=[ordered]@{type='string';minLength=1}
                        label=[ordered]@{type='string';minLength=1}
                        description=[ordered]@{type=@('string','null')}
                    }
                }
                HumanInputResponse=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('status','project_id')
                    properties=[ordered]@{
                        status=[ordered]@{type='string';enum=@('READY','NO_HUMAN_INPUT')}
                        project_id=[ordered]@{type='string';minLength=1}
                        request_id=[ordered]@{type='string';format='uuid'}
                        request_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        phase=[ordered]@{type='string'}
                        request_type=[ordered]@{type='string'}
                        context_summary=[ordered]@{type='string'}
                        question=[ordered]@{type='string'}
                        options=[ordered]@{type='array';items=[ordered]@{'$ref'='#/components/schemas/HumanInputOption'}}
                        authority_classification=[ordered]@{type='string'}
                        auto_define_stop_reason=[ordered]@{type=@('string','null')}
                        binding=[ordered]@{'$ref'='#/components/schemas/Binding'}
                    }
                }
                HumanInputSubmitRequest=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('request_sha256')
                    properties=[ordered]@{
                        request_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        selected_option_id=[ordered]@{type='string';minLength=1}
                        text=[ordered]@{type='string';minLength=1}
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
                        resume_ref=[ordered]@{type='string'}
                    }
                }
                SourceResponse=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('project_id','source_ref','sha256','byte_length','character_length','chunk_start','chunk_length','next_start','complete','content')
                    properties=[ordered]@{
                        project_id=[ordered]@{type='string';minLength=1}
                        source_ref=[ordered]@{type='string';minLength=1}
                        sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        byte_length=[ordered]@{type='integer';minimum=0;description='Full source byte length.'}
                        character_length=[ordered]@{type='integer';minimum=0;description='Full source UTF-16 character length.'}
                        chunk_start=[ordered]@{type='integer';minimum=0}
                        chunk_length=[ordered]@{type='integer';minimum=0;maximum=65536}
                        next_start=[ordered]@{type=@('integer','null');minimum=0}
                        complete=[ordered]@{type='boolean'}
                        content=[ordered]@{type='string'}
                    }
                }
                SubmitResultRequest=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('expected_parent_handoff_id','result')
                    properties=[ordered]@{
                        expected_parent_handoff_id=[ordered]@{type='string';format='uuid'}
                        summary=[ordered]@{type='string'}
                        result=[ordered]@{
                            type='object';additionalProperties=$false;description='Exact bound RUNTIME_ACTOR_RESULT or REVIEW_RESPONSE envelope. AIDOS Core validates the applicable full contract.'
                            required=@('schema_version','envelope_type','project_id','assignment_sha256','outcome','responded_at')
                            properties=[ordered]@{
                                schema_version=[ordered]@{type='string'};envelope_type=[ordered]@{type='string';enum=@('RUNTIME_ACTOR_RESULT','REVIEW_RESPONSE')}
                                assignment_id=[ordered]@{type='string'};assignment_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                                project_id=[ordered]@{type='string'};project_root=[ordered]@{type='string'};project_mode=[ordered]@{type='string'}
                                actor_role=[ordered]@{type='string'};actor_identity=[ordered]@{type='string'};action=[ordered]@{type='string'};binding=[ordered]@{type='object';additionalProperties=$true}
                                review_id=[ordered]@{type='string'};definition_id=[ordered]@{type='string'};definition_version=[ordered]@{type='integer'};execution_id=[ordered]@{type='string'};revision=[ordered]@{type='integer'}
                                reviewer_role=[ordered]@{type='string'};reviewer_identity=[ordered]@{type='string'};package_manifest_sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                                outcome=[ordered]@{type='string'};reason=[ordered]@{type='string'}
                                evidence_refs=[ordered]@{type='array';items=[ordered]@{type='object';additionalProperties=$false;required=@('kind','path','sha256');properties=[ordered]@{kind=[ordered]@{type='string'};path=[ordered]@{type='string'};sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}}}}
                                repair_guidance=[ordered]@{type='array';items=[ordered]@{type='string'}};result=[ordered]@{type='object';additionalProperties=$true}
                                responded_at=[ordered]@{type='string';format='date-time'};responded_by=[ordered]@{type='string'}
                            }
                        }
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
                    properties=[ordered]@{error=[ordered]@{type='string'};detail=[ordered]@{type='string'}}
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
        [IO.File]::Move($tmp,$full,$true)
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
    [pscustomobject][ordered]@{status='WRITTEN';path=$full;server_url=(Normalize-AidosRepositoryHandoffPublicUrl -ServerUrl $ServerUrl)}
}

Export-ModuleMember -Function Normalize-AidosRepositoryHandoffPublicUrl,New-AidosRepositoryHandoffOpenApiDocument,ConvertTo-AidosRepositoryHandoffOpenApiJson,Write-AidosRepositoryHandoffOpenApiDocument
