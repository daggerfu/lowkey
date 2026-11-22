# TODO

- [ ] Test the packaged `lowkeyctl` end to end: invoke the real executable, send a request over IPC, and assert its exit status, stdout/stderr and effects in the app. Cover cold launch, `status --json`, targeted open/hide/toggle without raising another site, `rewind`, page commands, upload and `wait --timeout`. Use an isolated bundle and configuration, random site IDs and a local demo page; never target the installed app or real profiles.

- [ ] Добавить возможность подключения sock proxy
- [ ] Конфиг в которм сайты на которые всегда заходить через прокси
 