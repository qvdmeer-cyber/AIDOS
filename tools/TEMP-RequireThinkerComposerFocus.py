from pathlib import Path

binding_path=Path('bridge/AidosRepositoryThinkerBinding.psm1')
binding=binding_path.read_text(encoding='utf-8')
old="    if(-not[bool]$composer.Current.HasKeyboardFocus -and -not[bool]$Context.window_is_foreground){throw 'ChatGPT composer focus proof is required before send.'}"
new="    if(-not[bool]$composer.Current.HasKeyboardFocus){throw 'ChatGPT composer keyboard focus proof is required before send.'}"
if binding.count(old)!=1:
    raise RuntimeError(f'focus guard expected once, found {binding.count(old)}')
binding=binding.replace(old,new)
binding_path.write_text(binding,encoding='utf-8')

test_path=Path('tests/RepositoryThinkerBinding.Tests.ps1')
test=test_path.read_text(encoding='utf-8')
anchor="Assert-Binding ($bindingSource.Contains(\"SendWait('{ENTER}')\")) 'Repository Thinker has a keyboard Enter fallback after exact composer proof'\n"
extra=anchor+"Assert-Binding ($bindingSource.Contains(\"if(-not[bool]`$composer.Current.HasKeyboardFocus){throw 'ChatGPT composer keyboard focus proof is required before send.'}\")) 'Repository Thinker requires explicit composer keyboard focus before clipboard or Enter input'\n"
if test.count(anchor)!=1:
    raise RuntimeError('test anchor missing or ambiguous')
test=test.replace(anchor,extra)
test_path.write_text(test,encoding='utf-8')
