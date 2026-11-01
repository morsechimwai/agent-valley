import { defineConfig } from '@playwright/test';

// The tests read the built site in out/, served as plain files, the way a host would serve it.
// Python's file server queues only 5 connections by default; Chrome asks for more at once and the
// rest are reset, so a script never arrives. The queue is raised to 128.
const SERVE =
  "python3 -c \"import functools,http.server as h; h.ThreadingHTTPServer.request_queue_size=128; " +
  "h.test(HandlerClass=functools.partial(h.SimpleHTTPRequestHandler,directory='out'),ServerClass=h.ThreadingHTTPServer,port=4321,bind='127.0.0.1')\"";
export default defineConfig({
  testDir: 'e2e',
  fullyParallel: true,
  reporter: 'list',
  use: { baseURL: 'http://127.0.0.1:4321', channel: 'chrome' },
  webServer: {
    command: SERVE,
    url: 'http://127.0.0.1:4321',
    reuseExistingServer: !process.env.CI,
    stderr: 'ignore',
  },
});
