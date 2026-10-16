# ~/.config/fish/config.fish  ·  Aurora shell

if status is-interactive
    set -g fish_greeting          # no "Welcome to fish" banner

    # prompt, smarter cd, fuzzy finder
    starship init fish | source
    zoxide init fish | source     # `z proj` jumps to ~/code/project
    fzf --fish | source           # Ctrl+R history search, Ctrl+T file search

    # nicer everyday commands
    alias ls 'eza --icons --group-directories-first'
    alias ll 'eza -la --icons --git --group-directories-first'
    alias tree 'eza --tree --icons --level=3'
    alias cat 'bat --paging=never --style=plain'

    # git shortcuts (type them, they expand)
    abbr -a g   git
    abbr -a gs  'git status -sb'
    abbr -a ga  'git add'
    abbr -a gc  'git commit -m'
    abbr -a gp  'git push'
    abbr -a gl  'git log --graph --oneline --decorate -20'
    abbr -a gd  'git diff'

    # system
    abbr -a up  'sudo pacman -Syu'
    abbr -a hy  'nvim ~/.config/hypr/hyprland.lua'
end

# ---- Aurora syntax colors ----
set -g fish_color_normal         e6edf7
set -g fish_color_command        6ee7c8
set -g fish_color_keyword        a78bfa
set -g fish_color_quote          f5d58a
set -g fish_color_redirection    67e8f9
set -g fish_color_end            a78bfa
set -g fish_color_error          ff7a90
set -g fish_color_param          c9d3e3
set -g fish_color_option         7cc4ff
set -g fish_color_comment        5b6780
set -g fish_color_operator       67e8f9
set -g fish_color_escape         f9a8d4
set -g fish_color_autosuggestion 5b6780
set -g fish_color_valid_path     --underline
set -g fish_color_search_match   --background=1b2235
set -g fish_color_selection      --background=1b2235
set -g fish_pager_color_prefix   6ee7c8 --bold
set -g fish_pager_color_completion c9d3e3
set -g fish_pager_color_description 5b6780
set -g fish_pager_color_progress 05080f --background=6ee7c8

# fzf in Aurora colors
set -gx FZF_DEFAULT_OPTS "--color=bg+:#1b2235,bg:-1,fg:#c9d3e3,fg+:#e6edf7,hl:#6ee7c8,hl+:#6ee7c8,info:#9aa6bb,prompt:#a78bfa,pointer:#6ee7c8,marker:#f9a8d4,spinner:#7cc4ff,header:#7cc4ff,border:#1b2235 --border=rounded --layout=reverse --height=40%"
