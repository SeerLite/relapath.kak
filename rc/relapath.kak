provide-module relapath %{
	declare-option str cwd
	declare-option str pretty_cwd
	declare-option -hidden str relapath_real_buffile
	declare-option str buffile
	declare-option str bufname
	alias global relapath-originalcmd-change-directory change-directory
	alias global relapath-originalcmd-edit edit
	alias global relapath-originalcmd-edit-bang edit!
	alias global relapath-originalcmd-rename-buffer rename-buffer

	evaluate-commands -buffer '*debug*' %{
		set-option buffer buffile %val{buffile}
		set-option buffer bufname %val{bufname}
	}

	# Use parent shell $PWD
	hook -once global ClientCreate .* %{
		evaluate-commands %sh{
			cwd="$kak_client_env_PWD"
			if [ "$cwd" -ef "$PWD" ]; then
				printf 'set-option global cwd "%s"\n' "$cwd"
			else
				printf 'set-option global cwd "%s"\n' "$PWD"
			fi

			eval "set -- $KAKOUNE_RELAPATH_KAK_ARGS"

			for arg in "$@"; do
				if [ -n "$arg" ] && [ "$(realpath -- "$arg" 2>/dev/null)" = "$kak_buffile" ]; then
					dir="$(dirname "$arg")"
					cd "$dir"
					file="$PWD/$(basename "$arg")"
					break
				fi
			done
			printf 'set-option buffer relapath_real_buffile "%s"\n' "$file"
		}
		relapath-check-buffiles-and-cwd
	}

	hook global BufSetOption (relapath_real_buffile|cwd)=.* %{
		set-option buffer bufname %sh{
			bufname="$(realpath -s --relative-to="$kak_opt_cwd" -- "$kak_opt_relapath_real_buffile" 2>/dev/null)"

			# Fall back to %val{bufname} if %opt{relapath_real_buffile} was empty or in a non-existing directory
			[ -z "$bufname" ] && bufname="$kak_bufname"

			# Abbreviate $HOME as ~
			[ "${bufname#$HOME}" != "$bufname" ] && bufname="~/${bufname#$HOME}"

			printf '%s' "$bufname"
		}
	}

	# So that %opt{buffile} falls back to %opt{bufname} like the builtin %vals
	hook global BufSetOption relapath_real_buffile=(.*) %{
		set-option buffer buffile %sh{
			relapath_real_buffile="$kak_hook_param_capture_1"
			if [ -n "$relapath_real_buffile" ]; then
				printf '%s' "$relapath_real_buffile"
			else
				printf '%s' "$kak_opt_bufname"
			fi
		}
	}

	hook global GlobalSetOption cwd=(.*) %{
		set-option global pretty_cwd %sh{
			pretty_cwd="$kak_hook_param_capture_1"

			# Abbreviate $HOME as ~
			[ "${pretty_cwd#$HOME}" != "$pretty_cwd" ] && pretty_cwd="~${pretty_cwd#$HOME}"

			printf '%s' "$pretty_cwd"
		}
	}

	define-command -hidden relapath-check-buffiles-and-cwd %{
		evaluate-commands %sh{
			if [ "$(realpath -- "$kak_opt_cwd" 2>/dev/null)" != "$(realpath -- "$PWD" 2>/dev/null)" ]; then
				printf 'echo -debug "%s"\n' "relapath.kak: Working directory '$kak_opt_cwd' doesn't match internal one. Falling back to '$PWD'."
				printf 'set-option global cwd "%s"\n' "$PWD"
			fi

			if [ "$kak_opt_buffile" != "$kak_buffile" ] && [ "$(realpath -- "$kak_opt_buffile" 2>/dev/null)" != "$kak_buffile" ]; then
				printf 'echo -debug "%s"\n' "relapath.kak: Path for buffer '$kak_bufname' ('$kak_opt_bufname') doesn't match. Falling back to %%val{buffile}: '$kak_buffile'."
				printf 'set-option buffer relapath_real_buffile "%s"\n' "$kak_buffile"
			fi
		}
	}

	hook global BufWritePost .* relapath-check-buffiles-and-cwd
	hook global NormalIdle .* relapath-check-buffiles-and-cwd

	# TODO: dir completions?
	define-command -file-completion -params ..1 relapath-change-directory %{
		evaluate-commands %sh{
			cd "$kak_opt_cwd"

			case "$1" in
				"")
					dir="$HOME"
					;;
				/*)
					dir="$1"
					;;
				~*)
					dir="${HOME}${1#\~}" # Expand ~ to $HOME
					;;
				*)
					dir="${kak_opt_cwd}/${1}"
					;;
			esac

			if [ ! -d "$dir" ]; then
				printf 'fail "relapath.kak: unable to cd to ""%s"""\n' "$dir"
				exit 1
			fi

			cd "$dir"
			printf 'set-option global cwd "%s"\n' "$PWD"
		}
		relapath-originalcmd-change-directory %opt{cwd}
	}

	define-command -hidden -file-completion -params .. relapath-edit-unwrapped %{
		# Will use edit or edit! depending on first argument passed by the wrapper commands
		%arg{@}
		evaluate-commands %sh{
			cd "$kak_opt_cwd"

			# Loop all parameters passed to :edit until finding one that matches same path as buffile
			for arg in "$@"; do
				if [ "$(realpath -- "$arg" 2>/dev/null)" = "$kak_buffile" ]; then
					file="$arg"

					dir="$(dirname "$file")"

					if [ ! -d "$dir" ]; then
						printf 'fail "relapath.kak: unable to cd to ""%s"""\n' "$dir"
						exit 1
					fi

					cd "$dir"
					file="$PWD/$(basename "$file")"

					# Remove double '/' when editing file at /
					[ "${file#//}" != "${file}" ] && file="/${file#//}"

					printf 'set-option buffer relapath_real_buffile "%s"\n' "$file"
					break
				fi
			done
		}
	}

	define-command -file-completion -params .. relapath-edit %{
		relapath-edit-unwrapped relapath-originalcmd-edit %arg{@}
	}

	define-command -file-completion -params .. relapath-edit-bang %{
		relapath-edit-unwrapped relapath-originalcmd-edit-bang %arg{@}
	}

	define-command -file-completion -params .. relapath-rename-buffer %{
		relapath-edit-unwrapped relapath-originalcmd-rename-buffer %arg{@}
	}

	define-command relapath-modelinefmt-replace -params 1 %{
		set-option %arg{1} modelinefmt %sh{
			printf '%s' "$kak_opt_modelinefmt" | sed 's/%val{\(bufname\|buffile\)}/%opt{\1}/g'
		}
	}

	define-command relapath-override-powerline -params 1 %{
		evaluate-commands %sh{
			sed -E 's/provide-module/provide-module -override/;s/kak_buf(name|file)/kak_opt_buf\1/g' "$1/rc/modules/bufname.kak"
		}

		hook global ModuleLoaded powerline %{
			hook global BufSetOption bufname=.* %{
				powerline-update-bufname
			}
		}
	}
}
