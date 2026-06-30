# agent-forge — agentic AI isolation platform shell config

# ---------- PATH ----------
export PATH="/usr/local/lib/package-age-gate/wrappers:$HOME/.local/bin:/usr/local/bin:$PATH"

# ---------- Prompt ----------
export PS1='\[\e[38;5;208m\]⚒ agent-forge\[\e[0m\] \[\e[38;5;39m\]\w\[\e[0m\] \$ '

# ---------- Aliases — AI Agents ----------
alias cc='claude'
alias oc='opencode'
alias cx='codex'
alias hm='hermes'

# ---------- Aliases — Local Models ----------
# OpenCode auto-discovers opencode.json in CWD for Ollama config.
#   Ensure Ollama is running on your host machine before using.
# Hermes (hm) is pre-wired to a local llama.cpp server on the host
#   (host.docker.internal:8080). Start llama-server with --host 0.0.0.0
#   so the container can reach it. Config: ~/.hermes/config.yaml

# ---------- Aliases — Security ----------
alias nse='ls /usr/share/nmap/scripts/'
alias serve='python3 -m http.server 8080'
alias listener='nc -lvnp'

# ---------- Aliases — General ----------
alias ll='ls -lahF --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias rg='rg --smart-case'
alias ..='cd ..'
alias ...='cd ../..'

# ---------- History ----------
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# ---------- Misc ----------
export EDITOR=vim
export TERM=xterm-256color

# Source completions if available
[ -f /etc/bash_completion ] && . /etc/bash_completion
