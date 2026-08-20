from pathlib import Path

path = Path('tests/RepositoryHandoffBootstrap.Tests.ps1')
text = path.read_text(encoding='utf-8')
old = "Assert-Bootstrap ($bridgeRuntime.Contains('& $script:AidosRepositoryReviewHandoffModule {')) 'runtime bridge invokes review publication through the imported module object'"
new = """Assert-Bootstrap ($bridgeRuntime.Contains(\"`$reviewPublisherCommand=`$reviewHandoffModules[0].ExportedCommands['Publish-AidosRepositoryReviewHandoff']\")) 'runtime bridge captures the exact review publisher CommandInfo before closure creation'
Assert-Bootstrap ($bridgeRuntime.Contains('& $reviewPublisherCommand -Project $Project -Push:$Push')) 'runtime bridge invokes the captured review publisher CommandInfo'
Assert-Bootstrap (-not$bridgeRuntime.Contains('& $script:AidosRepositoryReviewHandoffModule {')) 'runtime bridge does not resolve bridge script scope inside the review closure'"""
if old in text:
    if text.count(old) != 1:
        raise RuntimeError('obsolete bootstrap review publisher assertion is ambiguous')
    text = text.replace(old, new)
elif 'runtime bridge captures the exact review publisher CommandInfo before closure creation' not in text:
    raise RuntimeError('bootstrap review publisher assertion anchor missing')
path.write_text(text, encoding='utf-8')
