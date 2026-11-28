/* Prüft das Anmelde-Passwort eines Benutzers über PAM (wie Anmeldung und Bildschirmsperre).
 * Für Bestätigungen in Guardian und Tresor – aufgerufen nur von deren Diensten (root).
 * Aufruf: passwort-pruefen <benutzer>, Passwort als eine Zeile auf der Standardeingabe.
 * Rückgabe: 0 = richtig, 1 = falsch/gesperrt, 2 = Fehler. Liegt mit Rechten 0700 (nur root). */
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int gespraech(int n, const struct pam_message **nachricht, struct pam_response **antwort, void *daten)
{
    if (n <= 0 || n > 32) return PAM_CONV_ERR;
    struct pam_response *a = calloc((size_t)n, sizeof *a);
    if (!a) return PAM_BUF_ERR;
    for (int i = 0; i < n; ++i) {
        if (nachricht[i]->msg_style == PAM_PROMPT_ECHO_OFF || nachricht[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            a[i].resp = strdup((const char *)daten);
            if (!a[i].resp) { free(a); return PAM_BUF_ERR; }
        }
    }
    *antwort = a;
    return PAM_SUCCESS;
}

int main(int argc, char **argv)
{
    if (argc != 2 || geteuid() != 0 || argv[1][0] == '\0' || argv[1][0] == '-') return 2;
    char passwort[1024];
    if (!fgets(passwort, sizeof passwort, stdin)) return 2;
    passwort[strcspn(passwort, "\n")] = '\0';
    struct pam_conv gespraechspartner = { gespraech, passwort };
    pam_handle_t *h = NULL;
    int r = pam_start("auriliux-bestaetigen", argv[1], &gespraechspartner, &h);
    if (r != PAM_SUCCESS) { explicit_bzero(passwort, sizeof passwort); return 2; }
    r = pam_authenticate(h, PAM_DISALLOW_NULL_AUTHTOK);
    if (r == PAM_SUCCESS) r = pam_acct_mgmt(h, PAM_DISALLOW_NULL_AUTHTOK);
    pam_end(h, r);
    explicit_bzero(passwort, sizeof passwort);
    return r == PAM_SUCCESS ? 0 : 1;
}
