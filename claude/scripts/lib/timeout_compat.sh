#!/bin/bash
# macOS互換のtimeout関数
# macOSにはGNU timeoutがないため、perlのalarm/forkで代替
# 使用方法: source ~/.claude/scripts/lib/timeout_compat.sh

if ! command -v timeout &>/dev/null; then
    timeout() {
        local secs="${1%s}"
        shift
        perl -e '
            my $timeout = shift;
            my $pid = fork();
            die "fork failed: $!" unless defined $pid;
            if ($pid == 0) {
                exec @ARGV;
                exit 127;
            }
            local $SIG{ALRM} = sub { kill "TERM", $pid; };
            alarm $timeout;
            waitpid($pid, 0);
            alarm 0;
            exit ($? & 127 ? 128 + ($? & 127) : $? >> 8);
        ' "$secs" "$@"
    }
fi
