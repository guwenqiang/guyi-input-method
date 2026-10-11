#ifndef GUYI_RIME_BRIDGE_H
#define GUYI_RIME_BRIDGE_H
#include <stdint.h>
int guyi_rime_start(const char *shared, const char *user);
uintptr_t guyi_rime_session(void);
void guyi_rime_destroy(uintptr_t session);
int guyi_rime_key(uintptr_t session, int key);
void guyi_rime_clear(uintptr_t session);
int guyi_rime_select_schema(uintptr_t session, const char *schema);
void guyi_rime_finish(uintptr_t session);
int guyi_rime_cursor(uintptr_t session);
int guyi_rime_page(uintptr_t session);
int guyi_rime_last_page(uintptr_t session);
void guyi_rime_highlight(uintptr_t session, int index);
char *guyi_rime_raw(uintptr_t session);
int guyi_rime_select(uintptr_t session, int index);
char *guyi_rime_state(uintptr_t session);
char *guyi_rime_commit(uintptr_t session);
void guyi_rime_free(char *value);
#endif
