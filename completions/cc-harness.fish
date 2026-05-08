# cc-harness fish completion
function __cch_labels
    cc-harness list 2>/dev/null | awk 'NR>1 {print $1}'
end
function __cch_tags
    cc-harness list --tags 2>/dev/null | awk '{sub(/^#/,"",$1); print $1}'
end
complete -c cc-harness -f -n '__fish_use_subcommand' -a 'attach new kill list add remove rename tag untag status doctor logs which completion version'
complete -c cc-harness -n '__fish_seen_subcommand_from new kill logs which rename remove tag untag' -a '(__cch_labels)'
complete -c cc-harness -l tag -a '(__cch_tags)'
complete -c cc-harness -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
