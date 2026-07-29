if [[ -z "${VIVARIUM_PROMPT-}" ]]; then
  PROMPT='%m:%~%# '
else
  PROMPT="${VIVARIUM_PROMPT}"
fi

PS1="${PROMPT}"
