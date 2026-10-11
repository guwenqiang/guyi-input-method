#include "CRimeBridge.h"
#include <rime_api.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

static RimeApi *api;
char *guyi_rime_raw(uintptr_t session) {
    const char *text = api && session ? api->get_input(session) : NULL;
    return strdup(text ? text : "");
}

int guyi_rime_start(const char *shared, const char *user) {
    if (api) return 1;
    api = rime_get_api();
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = shared;
    traits.user_data_dir = user;
    traits.app_name = "rime.guyi";
    traits.distribution_name = "guyi";
    traits.distribution_code_name = "guyi";
    traits.distribution_version = "0.1.0";
    traits.min_log_level = 3;
    traits.log_dir = user;
    api->setup(&traits);
    api->initialize(&traits);
    if (api->start_maintenance(False)) api->join_maintenance_thread();
    for (int index = 0; index < 2; index++) {
        const char *name = index == 0 ? "jaroomaji.schema.yaml" : "guyi_japanese_private.schema.yaml";
        char path[PATH_MAX];
        int length = snprintf(path, sizeof(path), "%s/%s", shared, name);
        if (length > 0 && length < (int)sizeof(path)) api->deploy_schema(path);
    }
    return 1;
}

uintptr_t guyi_rime_session(void) {
    if (!api) return 0;
    RimeSessionId session = api->create_session();
    if (!api->select_schema(session, "guyi_pinyin")) {
        api->destroy_session(session);
        return 0;
    }
    api->set_option(session, "simplification", True);
    return session;
}

void guyi_rime_destroy(uintptr_t session) { if (api && session) api->destroy_session(session); }
int guyi_rime_key(uintptr_t session, int key) { return api && session ? api->process_key(session, key, 0) : 0; }
void guyi_rime_clear(uintptr_t session) { if (api && session) api->clear_composition(session); }
int guyi_rime_select_schema(uintptr_t session, const char *schema) {
    if (!api || !session || !schema) return 0;
    RIME_STRUCT(RimeStatus, status);
    if (api->get_status(session, &status)) {
        int changed = strcmp(status.schema_id, schema);
        api->free_status(&status);
        if (!changed) return 1;
    }
    if (!api->select_schema(session, schema)) return 0;
    api->set_option(session, "ascii_mode", False);
    if (strcmp(schema, "guyi_pinyin") == 0 || strcmp(schema, "guyi_private") == 0)
        api->set_option(session, "simplification", True);
    return 1;
}
void guyi_rime_finish(uintptr_t session) { if (api && session) api->commit_composition(session); }
int guyi_rime_select(uintptr_t session, int index) {
    return api && session ? api->select_candidate_on_current_page(session, index) : 0;
}

int guyi_rime_cursor(uintptr_t session) {
    RIME_STRUCT(RimeContext, context);
    if (!api || !session || !api->get_context(session, &context)) return 0;
    int cursor = context.composition.cursor_pos;
    api->free_context(&context);
    return cursor;
}
int guyi_rime_page(uintptr_t session) {
    RIME_STRUCT(RimeContext, context);
    if (!api || !session || !api->get_context(session, &context)) return 0;
    int page = context.menu.page_no;
    api->free_context(&context);
    return page;
}
int guyi_rime_last_page(uintptr_t session) {
    RIME_STRUCT(RimeContext, context);
    if (!api || !session || !api->get_context(session, &context)) return 1;
    int last = context.menu.is_last_page;
    api->free_context(&context);
    return last;
}
void guyi_rime_highlight(uintptr_t session, int index) {
    if (api && session && RIME_API_AVAILABLE(api, highlight_candidate_on_current_page)) {
        api->highlight_candidate_on_current_page(session, index);
    }
}

char *guyi_rime_state(uintptr_t session) {
    RIME_STRUCT(RimeContext, context);
    if (!api || !session || !api->get_context(session, &context)) return strdup("");
    const char *preview = context.commit_text_preview ? context.commit_text_preview : "";
    size_t size = strlen(context.composition.preedit ? context.composition.preedit : "") + strlen(preview) + 32;
    for (int index = 0; index < context.menu.num_candidates; index++) size += strlen(context.menu.candidates[index].text) + 1;
    char *buffer = calloc(size, 1);
    if (buffer) {
        strcat(buffer, context.composition.preedit ? context.composition.preedit : "");
        strcat(buffer, "\n");
        strcat(buffer, preview);
        strcat(buffer, "\n");
        char selected[16];
        snprintf(selected, sizeof(selected), "%d\n", context.menu.highlighted_candidate_index);
        strcat(buffer, selected);
        for (int index = 0; index < context.menu.num_candidates; index++) {
            strcat(buffer, context.menu.candidates[index].text);
            strcat(buffer, "\n");
        }
    }
    api->free_context(&context);
    return buffer;
}

char *guyi_rime_commit(uintptr_t session) {
    RIME_STRUCT(RimeCommit, commit);
    if (!api || !session || !api->get_commit(session, &commit)) return strdup("");
    char *value = strdup(commit.text ? commit.text : "");
    api->free_commit(&commit);
    return value;
}

void guyi_rime_free(char *value) { free(value); }
