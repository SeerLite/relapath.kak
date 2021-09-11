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
				printf 'set-option global cwd "%s";' "$cwd"
			else
				printf 'set-option global cwd "%s";' "$PWD"
			fi

			eval "set -- $KAKOUNE_RELAPATH_KAK_ARGS"

			for arg in "$@"; do
				if [ -n "$arg" ] && [ "$(realpath -- "$arg" 2>/dev/null)" = "$kak_buffile" ]; then
					dir="${arg%/*}"
					[ "$dir" = "$arg" ] && dir=.
					cd "$dir"
					file="$PWD/${arg##*/}"
					break
				fi
			done
			[ -z "$file" ] && file="$kak_buffile"
			printf 'set-option buffer relapath_real_buffile "%s"' "$file"
		}
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

	define-command -hidden relapath-check-buffiles-match %{
		evaluate-commands %sh{
			if [ "$kak_buffile" != "$kak_opt_buffile" ] && [ "$(realpath -- "$kak_opt_buffile" 2>/dev/null)" != "$kak_buffile" ]; then
				printf 'echo -debug "%s";' "relapath.kak: Path for buffer '$kak_opt_bufname' doesn't match. Falling back to %%val{buffile}: '$kak_buffile'."
				printf 'set-option buffer relapath_real_buffile "%s"' "$kak_buffile"
			fi
		}
	}

	hook global BufWritePost .* relapath-check-buffiles-match
	hook global NormalIdle .* relapath-check-buffiles-match

	# TODO: dir completions?
	define-command -file-completion -params ..1 relapath-change-directory %{
		evaluate-commands %sh{
			cd "$kak_opt_cwd"

			case "$1" in
				"")
					directory="$HOME"
					;;
				/*)
					directory="$1"
					;;
				~*)
					directory="${HOME}${1#\~}" # Expand ~ to $HOME
					;;
				*)
					directory="${kak_opt_cwd}/${1}"
					;;
			esac

			if [ ! -d "$directory" ]; then
				printf 'fail "unable to cd to ""%s"""\n' "$directory"
				exit 1
			fi

			cd "$directory"
			printf 'set-option global cwd "%s"' "$PWD"
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

					dir="${file%/*}"
					[ "$dir" = "$file" ] && dir=.

					if [ ! -d "$dir" ]; then
						printf 'fail "unable to cd to ""%s"""\n' "$dir"
						exit 1
					fi

					cd "$dir"
					file="$PWD/${file##*/}"

					# Remove double '/' when editing file at /
					[ "${file#//}" != "${file}" ] && file="/${file#//}"

					printf 'set-option buffer relapath_real_buffile "%s"' "$file"
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
