#ifndef LOWKEY_CGTK_H
#define LOWKEY_CGTK_H

/*
 * Header-only bridge between LowkeyLinux (Swift) and GTK 4 / WebKitGTK 6.0.
 * Swift cannot call GLib macros or variadics, so every operation the app needs
 * lives here as a plain function. Signal callbacks match the real GLib handler
 * shapes (instance pointer first, user data last); Swift passes global
 * trampolines and boxes itself into `user_data`.
 *
 * Build dependency (Ubuntu): sudo apt install libwebkitgtk-6.0-dev
 */

#include <gtk/gtk.h>
#include <webkit/webkit.h>

/* g_idle_add source: gboolean (*)(gpointer). Return 0 (G_SOURCE_REMOVE). */
typedef int (*CGTKIdleFunc)(void *userdata);
/* activate / shutdown / destroy / clicked: void (*)(gpointer instance, gpointer user_data) */
typedef void (*CGTKNotifyFunc)(void *instance, void *userdata);
/* close-request: gboolean (*)(gpointer instance, gpointer user_data) */
typedef int (*CGTKCloseFunc)(void *instance, void *userdata);
/* load-changed: void (*)(WebKitWebView*, WebKitLoadEvent, gpointer) */
typedef void (*CGTKLoadFunc)(void *webView, int event, void *userdata);
/* Prompt result: NULL text means cancelled. */
typedef void (*CGTKStringFunc)(const char *text, void *userdata);

/* MARK: - Application */

static inline GtkApplication *cgtk_application_new(const char *id) {
    return gtk_application_new(id, G_APPLICATION_DEFAULT_FLAGS);
}

static inline void cgtk_application_on_activate(GtkApplication *app, CGTKNotifyFunc cb, void *userdata) {
    g_signal_connect_data(app, "activate", G_CALLBACK(cb), userdata, NULL, (GConnectFlags)0);
}

static inline void cgtk_application_on_shutdown(GtkApplication *app, CGTKNotifyFunc cb, void *userdata) {
    g_signal_connect_data(app, "shutdown", G_CALLBACK(cb), userdata, NULL, (GConnectFlags)0);
}

static inline int cgtk_application_run(GtkApplication *app, int argc, char **argv) {
    return g_application_run(G_APPLICATION(app), argc, argv);
}

static inline void cgtk_application_quit(GtkApplication *app) {
    g_application_quit(G_APPLICATION(app));
}

/* Runs `cb` on the GTK main thread (the only thread allowed to touch widgets). */
static inline void cgtk_invoke_on_main(CGTKIdleFunc cb, void *userdata) {
    g_idle_add((GSourceFunc)cb, userdata);
}

/* MARK: - Windows */

static inline GtkWidget *cgtk_window_new(GtkApplication *app, const char *title) {
    GtkWidget *window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), 1024, 768);
    return window;
}

static inline void cgtk_window_present(GtkWidget *window) {
    gtk_window_present(GTK_WINDOW(window));
}

static inline void cgtk_window_hide(GtkWidget *window) {
    gtk_widget_set_visible(window, FALSE);
}

static inline int cgtk_window_visible(GtkWidget *window) {
    return gtk_widget_get_visible(window) ? 1 : 0;
}

static inline int cgtk_window_active(GtkWidget *window) {
    return gtk_window_is_active(GTK_WINDOW(window)) ? 1 : 0;
}

static inline void cgtk_window_destroy(GtkWidget *window) {
    gtk_window_destroy(GTK_WINDOW(window));
}

static inline void cgtk_window_on_close_request(GtkWidget *window, CGTKCloseFunc cb, void *userdata) {
    g_signal_connect_data(window, "close-request", G_CALLBACK(cb), userdata, NULL, (GConnectFlags)0);
}

static inline void cgtk_window_on_destroy(GtkWidget *window, CGTKNotifyFunc cb, void *userdata) {
    g_signal_connect_data(window, "destroy", G_CALLBACK(cb), userdata, NULL, (GConnectFlags)0);
}

/* MARK: - Header bar controls */

static inline GtkWidget *cgtk_header_bar_button(GtkWidget *window, const char *label,
                                                CGTKNotifyFunc cb, void *userdata) {
    GtkWidget *header = gtk_header_bar_new();
    gtk_window_set_titlebar(GTK_WINDOW(window), header);
    GtkWidget *button = gtk_button_new_with_label(label);
    g_signal_connect_data(button, "clicked", G_CALLBACK(cb), userdata, NULL, (GConnectFlags)0);
    gtk_header_bar_pack_start(GTK_HEADER_BAR(header), button);
    return button;
}

static inline void cgtk_header_bar_title(GtkWidget *window, const char *title) {
    GtkWidget *header = gtk_window_get_titlebar(GTK_WINDOW(window));
    if (header != NULL) gtk_header_bar_set_title_widget(GTK_HEADER_BAR(header), gtk_label_new(title));
}

/* MARK: - Web views */

/*
 * Creates a web view with its own WebKitWebContext backed by `data_dir`
 * (the site's persistent profile) and, when `socks5` is "host:port", routes the
 * context's traffic through that SOCKS5 proxy, keeping loopback direct.
 * `socks5` is read during the call only.
 */
static inline WebKitWebView *cgtk_webview_new_in_window(GtkWidget *window, const char *data_dir,
                                                        const char *socks5) {
    WebKitWebsiteDataManager *manager = webkit_website_data_manager_new("base-data-directory", data_dir, NULL);
    WebKitWebContext *context = webkit_web_context_new_with_website_data_manager(manager);
    g_object_unref(manager);
    if (socks5 != NULL) {
        gchar *uri = g_strdup_printf("socks5://%s", socks5);
        const gchar *const ignore[] = { "localhost", "127.0.0.1", "::1", NULL };
        WebKitNetworkProxySettings *settings = webkit_network_proxy_settings_new(uri, ignore);
        webkit_web_context_set_network_proxy_settings(context, WEBKIT_NETWORK_PROXY_MODE_CUSTOM, settings);
        webkit_network_proxy_settings_free(settings);
        g_free(uri);
    }
    WebKitWebView *webView = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(context));
    g_object_unref(context);
    gtk_window_set_child(GTK_WINDOW(window), GTK_WIDGET(webView));
    /* The window title follows the page title without a Swift callback. */
    g_object_bind_property(webView, "title", window, "title", G_BINDING_SYNC_CREATE);
    return webView;
}

static inline void cgtk_webview_load(WebKitWebView *webView, const char *uri) {
    webkit_web_view_load_uri(webView, uri);
}

static inline const char *cgtk_webview_uri(WebKitWebView *webView) {
    return webkit_web_view_get_uri(webView);
}

static inline const char *cgtk_webview_title(WebKitWebView *webView) {
    const char *title = webkit_web_view_get_title(webView);
    return title != NULL ? title : "";
}

static inline int cgtk_webview_loading(WebKitWebView *webView) {
    return webkit_web_view_is_loading(webView) ? 1 : 0;
}

static inline int cgtk_webview_can_back(WebKitWebView *webView) {
    return webkit_web_view_can_go_back(webView) ? 1 : 0;
}

static inline int cgtk_webview_can_forward(WebKitWebView *webView) {
    return webkit_web_view_can_go_forward(webView) ? 1 : 0;
}

static inline void cgtk_webview_back(WebKitWebView *webView) {
    webkit_web_view_go_back(webView);
}

static inline void cgtk_webview_forward(WebKitWebView *webView) {
    webkit_web_view_go_forward(webView);
}

static inline void cgtk_webview_reload(WebKitWebView *webView) {
    webkit_web_view_reload(webView);
}

static inline void cgtk_webview_stop(WebKitWebView *webView) {
    webkit_web_view_stop_loading(webView);
}

static inline void cgtk_webview_on_load_changed(WebKitWebView *webView, CGTKLoadFunc cb, void *userdata) {
    g_signal_connect_data(webView, "load-changed", G_CALLBACK(cb), userdata, NULL, (GConnectFlags)0);
}

/* MARK: - Address prompt */

typedef struct {
    CGTKStringFunc func;
    void *userdata;
} CGTKPromptClosure;

G_GNUC_UNUSED static void cgtk_prompt_response(GtkDialog *dialog, gint response, gpointer ptr) {
    CGTKPromptClosure *closure = (CGTKPromptClosure *)ptr;
    GtkWidget *entry = GTK_WIDGET(g_object_get_data(G_OBJECT(dialog), "cgtk-entry"));
    const char *text = entry != NULL ? gtk_editable_get_text(GTK_EDITABLE(entry)) : "";
    closure->func(response == GTK_RESPONSE_OK ? text : NULL, closure->userdata);
    g_free(closure);
    gtk_window_destroy(GTK_WINDOW(dialog));
}

/* `cb` receives the entered text, or NULL when cancelled. */
static inline void cgtk_prompt(GtkWindow *parent, const char *title, const char *prefill,
                               CGTKStringFunc cb, void *userdata) {
    GtkWidget *dialog = gtk_dialog_new_with_buttons(title, parent, GTK_DIALOG_MODAL,
                                                    "_Cancel", GTK_RESPONSE_CANCEL,
                                                    "_Open", GTK_RESPONSE_OK, NULL);
    GtkWidget *entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "site alias or address");
    if (prefill != NULL) gtk_editable_set_text(GTK_EDITABLE(entry), prefill);
    gtk_widget_set_size_request(entry, 380, -1);
    gtk_box_append(GTK_BOX(gtk_dialog_get_content_area(GTK_DIALOG(dialog))), entry);
    g_object_set_data_full(G_OBJECT(dialog), "cgtk-entry", g_object_ref(entry), g_object_unref);
    CGTKPromptClosure *closure = g_new(CGTKPromptClosure, 1);
    closure->func = cb;
    closure->userdata = userdata;
    g_signal_connect_data(dialog, "response", G_CALLBACK(cgtk_prompt_response), closure, NULL, (GConnectFlags)0);
    gtk_widget_show(dialog);
}

#endif /* LOWKEY_CGTK_H */
