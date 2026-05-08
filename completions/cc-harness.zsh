#compdef cc-harness
_cc_harness() {
    local -a cmds
    cmds=(
        'attach:attach the harness session'
        'new:spawn a new claude session'
        'kill:kill an existing claude session'
        'list:list configured projects'
        'add:add a project'
        'remove:remove a project'
        'rename:rename a project'
        'tag:add/remove tags on a project'
        'untag:strip all tags from a project'
        'status:show running session status'
        'doctor:run environment checks'
        'logs:capture pane output for a project'
        'which:print resolved path of a project'
        'completion:emit shell completion'
        'version:print version'
    )
    if (( CURRENT == 2 )); then
        _describe 'command' cmds
    else
        case "$words[2]" in
            new|kill|logs|which|rename|remove|tag|untag)
                local -a labels
                labels=(${(f)"$(cc-harness list 2>/dev/null | awk 'NR>1 {print $1}')"})
                _describe 'project' labels ;;
            completion)
                _arguments '*:shell:(bash zsh fish)' ;;
        esac
    fi
}
_cc_harness "$@"
