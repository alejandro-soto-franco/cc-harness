# cc-harness bash completion
_cc_harness() {
    local cur prev cmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmds="attach new kill list add remove rename tag untag status doctor logs which completion version --version --help -h"
    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
        return 0
    fi
    case "$prev" in
        new|kill|logs|which|rename|remove|tag|untag)
            local labels
            labels=$(cc-harness list 2>/dev/null | awk 'NR>1 {print $1}')
            COMPREPLY=( $(compgen -W "$labels" -- "$cur") )
            ;;
        --tag)
            local tags
            tags=$(cc-harness list --tags 2>/dev/null | awk '{sub(/^#/,"",$1); print $1}')
            COMPREPLY=( $(compgen -W "$tags" -- "$cur") )
            ;;
        completion)
            COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
            ;;
    esac
}
complete -F _cc_harness cc-harness
