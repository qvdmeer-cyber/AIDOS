from pathlib import Path

reload_path = Path('tools/Reload-AidosAutonomousPreparation.ps1')
reload = reload_path.read_text(encoding='utf-8')
duplicate = '-PreserveExistingTask:$PreserveSelfUpdateTask -PreserveExistingTask:$PreserveSelfUpdateTask'
single = '-PreserveExistingTask:$PreserveSelfUpdateTask'
count = reload.count(duplicate)
if count != 1:
    raise RuntimeError(f'expected exactly one duplicate preservation argument sequence, found {count}')
reload = reload.replace(duplicate, single)
reload_path.write_text(reload, encoding='utf-8')

test_path = Path('tests/HostSelfUpdateContract.Tests.ps1')
test = test_path.read_text(encoding='utf-8')
anchor = "Assert-SelfUpdate ($reload -match 'PreserveSelfUpdateTask' -and $reload -match '-PreserveExistingTask:\\$PreserveSelfUpdateTask') 'reload propagates explicit self-update task preservation'\n"
extra = anchor + "Assert-SelfUpdate (([regex]::Matches($reload,'-PreserveExistingTask:\\$PreserveSelfUpdateTask')).Count -eq 1) 'reload passes self-update task preservation to the installer exactly once'\n"
if extra not in test:
    if test.count(anchor) != 1:
        raise RuntimeError('host self-update preservation assertion anchor missing or ambiguous')
    test = test.replace(anchor, extra)
test_path.write_text(test, encoding='utf-8')
