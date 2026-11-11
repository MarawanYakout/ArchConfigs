/*
 * secreport - run the security checks, save a timestamped report, show it.
 *
 *   secreport       scan, save, notify, open the report in a terminal window
 *   secreport -n    scan and save only, print the report path (no window)
 *
 * The checks themselves are in checks.sh. This program times the run,
 * writes ~/Documents/security-reports/security-report_<date>_<time>.txt
 * with a summary on top, sends a notification and opens the file.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECKS    ".local/share/secreport/checks.sh"
#define STATEDIR  ".local/share/secreport/state"
#define REPORTDIR "Documents/security-reports"

/* Run argv and wait. If out is set, stdout+stderr go to that file. */
static int run(char *const argv[], const char *out)
{
    pid_t pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        if (out) {
            int fd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0600);
            if (fd < 0)
                _exit(127);
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
            close(fd);
        }
        execvp(argv[0], argv);
        _exit(127);
    }
    int status;
    if (waitpid(pid, &status, 0) < 0)
        return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void notify(const char *urgency, const char *title, const char *body)
{
    char *argv[] = { "notify-send", "-a", "system", "-u", (char *)urgency,
                     (char *)title, (char *)body, NULL };
    run(argv, "/dev/null");
}

/* mkdir -p with mode 0700 for the last part */
static int make_dir(const char *path)
{
    char buf[4096];
    snprintf(buf, sizeof buf, "%s", path);
    for (char *p = buf + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(buf, 0755) < 0 && errno != EEXIST)
                return -1;
            *p = '/';
        }
    }
    if (mkdir(buf, 0700) < 0 && errno != EEXIST)
        return -1;
    return 0;
}

static int starts_with(const char *s, const char *prefix)
{
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

int main(int argc, char **argv)
{
    int show = !(argc > 1 && strcmp(argv[1], "-n") == 0);
    const char *home = getenv("HOME");
    if (!home) {
        fputs("secreport: HOME is not set\n", stderr);
        return 1;
    }

    char dir[4096], checks[4096], state[4096], raw[4200], report[4200];
    char stamp[32], when[32], host[256] = "?";
    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    strftime(stamp, sizeof stamp, "%Y-%m-%d_%H-%M-%S", tm);
    strftime(when, sizeof when, "%Y-%m-%d %H:%M:%S", tm);
    gethostname(host, sizeof host - 1);

    snprintf(dir, sizeof dir, "%s/%s", home, REPORTDIR);
    snprintf(checks, sizeof checks, "%s/%s", home, CHECKS);
    snprintf(state, sizeof state, "%s/%s", home, STATEDIR);
    snprintf(report, sizeof report, "%s/security-report_%s.txt", dir, stamp);
    snprintf(raw, sizeof raw, "%s/.scan_%s.tmp", dir, stamp);

    if (make_dir(dir) < 0) {
        perror("secreport: cannot create report folder");
        notify("critical", "Security report", "Cannot create the report folder");
        return 1;
    }

    if (show)
        notify("low", "Security scan running", "Checking ports, connections, processes...");
    else
        fprintf(stderr, "scanning...\n");

    char *scan[] = { "/bin/bash", checks, state, NULL };
    int rc = run(scan, raw);

    FILE *in = fopen(raw, "r");
    FILE *out = fopen(report, "w");
    if (!in || !out) {
        perror("secreport: cannot write report");
        notify("critical", "Security report", "Scan failed - could not write the report");
        return 1;
    }

    /* pass 1: count findings */
    char *line = NULL;
    size_t cap = 0;
    int alerts = 0, warns = 0;
    while (getline(&line, &cap, in) > 0) {
        if (starts_with(line, "[ALERT]"))
            alerts++;
        else if (starts_with(line, "[WARN]"))
            warns++;
    }

    fprintf(out, "SECURITY REPORT\n");
    fprintf(out, "Host:   %s\nDate:   %s\nFile:   %s\n\n", host, when, report);
    if (rc != 0)
        fprintf(out, "NOTE:   the check script exited with code %d - report may be incomplete\n\n", rc);
    if (alerts == 0 && warns == 0)
        fprintf(out, "RESULT: CLEAN - nothing suspicious found\n");
    else
        fprintf(out, "RESULT: %d alert(s), %d warning(s)\n", alerts, warns);
    fprintf(out, "        ALERT = possible compromise, look now\n"
                 "        WARN  = worth a look: risky setting or something new since last scan\n");

    /* pass 2: findings list */
    fprintf(out, "\n==== FINDINGS ====\n");
    rewind(in);
    while (getline(&line, &cap, in) > 0)
        if (starts_with(line, "[ALERT]") || starts_with(line, "[WARN]"))
            fputs(line, out);
    if (alerts == 0 && warns == 0)
        fputs("(none)\n", out);

    /* pass 3: full details */
    fprintf(out, "\n\n######## FULL DETAILS ########\n");
    rewind(in);
    while (getline(&line, &cap, in) > 0)
        fputs(line, out);

    free(line);
    fclose(in);
    fclose(out);
    unlink(raw);
    chmod(report, 0600);

    char body[4400];
    if (alerts == 0 && warns == 0)
        snprintf(body, sizeof body, "CLEAN - nothing suspicious\n%s", report);
    else
        snprintf(body, sizeof body, "%d alert(s), %d warning(s)\n%s", alerts, warns, report);
    if (show)
        notify(alerts ? "critical" : "normal", "Security report ready", body);

    if (!show) {
        printf("%s\n", report);
        return alerts ? 2 : 0;
    }

    execlp("alacritty", "alacritty", "--title", "Security Report",
           "-e", "less", report, (char *)NULL);
    execlp("xdg-open", "xdg-open", report, (char *)NULL);   /* fallback */
    perror("secreport: cannot open a viewer");
    return 1;
}
