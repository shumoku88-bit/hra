#define _XOPEN_SOURCE 700

#include <limits.h>
#include <locale.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* Provided by the wide-character ncurses library selected by AdaCurses. */
extern int mvaddnwstr(int line, int column, const wchar_t *text, int length);

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
    const char *source;
    size_t wide_length;
    size_t converted;
    size_t count;
    int columns;
    int result;
    wchar_t *wide;

    if (text == NULL || text[0] == '\0' || max_columns <= 0) {
        return 0;
    }

    memset(&state, 0, sizeof(state));
    source = text;
    wide_length = mbsrtowcs(NULL, &source, 0, &state);
    if (wide_length == (size_t)-1 || wide_length > (size_t)INT_MAX) {
        return -1;
    }

    wide = calloc(wide_length + 1, sizeof(*wide));
    if (wide == NULL) {
        return -1;
    }

    memset(&state, 0, sizeof(state));
    source = text;
    converted = mbsrtowcs(wide, &source, wide_length + 1, &state);
    if (converted == (size_t)-1) {
        free(wide);
        return -1;
    }

    columns = 0;
    count = 0;
    while (count < converted) {
        int width = wcwidth(wide[count]);

        if (width < 0) {
            free(wide);
            return -1;
        }
        if (columns + width > max_columns) {
            break;
        }

        columns += width;
        ++count;
    }

    if (count == 0) {
        free(wide);
        return 0;
    }

    result = mvaddnwstr(line, column, wide, (int)count);
    free(wide);
    return result;
}
