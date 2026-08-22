#define _XOPEN_SOURCE 700

#include <limits.h>
#include <locale.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* Provided by the standard narrow ncurses library selected by AdaCurses. */
extern int mvaddnstr(int line, int column, const char *text, int length);

int hra_terminal_utf8_initialize(void)
{
    return setlocale(LC_ALL, "") == NULL ? -1 : 0;
}

int hra_terminal_utf8_add_line(int line,
                               int column,
                               const char *text,
                               int max_columns)
{
    mbstate_t state;
    const char *ptr;
    size_t remaining;
    int columns = 0;
    int bytes_to_draw = 0;

    if (text == NULL || text[0] == '\0' || max_columns <= 0) {
        return 0;
    }

    memset(&state, 0, sizeof(state));
    ptr = text;
    remaining = strlen(text);

    while (remaining > 0) {
        wchar_t wc;
        size_t consumed = mbrtowc(&wc, ptr, remaining, &state);
        int width;

        if (consumed == (size_t)-1 || consumed == (size_t)-2) {
            return -1;
        }
        if (consumed == 0) {
            break;
        }

        width = wcwidth(wc);
        if (width < 0) {
            return -1;
        }

        if (columns + width > max_columns) {
            break;
        }

        columns += width;
        bytes_to_draw += (int)consumed;
        ptr += consumed;
        remaining -= consumed;
    }

    if (bytes_to_draw == 0) {
        return 0;
    }

    return mvaddnstr(line, column, text, bytes_to_draw);
}
