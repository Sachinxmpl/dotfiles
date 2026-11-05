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


# colours + fzf follow the wallpaper: matugen writes ~/.config/fish/aurora-colors.fish (universal vars)
