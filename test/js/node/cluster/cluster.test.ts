import { expect, test } from "bun:test";
import path from "node:path";
import "harness";

function new_test(name: string) {
  test(name, () => {
    expect([path.join(import.meta.dir, "fixtures", name)]).toRun();
  });
}

new_test("cwd.ts");
new_test("call-and-destroy.ts");
new_test("worker-constructor.ts");
new_test("worker-death.ts");
new_test("worker-events.ts");
new_test("worker-forced-exit.ts");
new_test("advanced-serialization.ts");
new_test("disconnect-with-no-workers.ts");
new_test("fork-env.ts");
new_test("kill-infinite-loop.ts");
new_test("process-disconnect.ts");
new_test("setup-primary-argv.ts");
new_test("setup-primary-emit.ts");
new_test("setup-primary-multiple.ts");
new_test("setup-primary.ts");
new_test("uncaught-exception.ts");
new_test("disconnect-before-exit.ts");
new_test("disconnect-exitedAfterDisconnect-race.ts");
new_test("disconnect-idle-worker.ts");
new_test("invalid-message.ts");
new_test("kill-disconnect.ts");
new_test("listening-port.ts");
new_test("rr-ref.ts");
new_test("send-deadlock.ts");
new_test("worker-init.ts");
new_test("setup-primary-cumulative.ts");
new_test("rr-handle-keep-loop-alive.ts");
new_test("worker-exit.ts");
new_test("disconnect-leak.ts");
new_test("worker-destroy.ts");
new_test("worker-isdead.ts");
new_test("rr-handle-ref-unref.ts");
new_test("rr-handle-close.ts");
new_test("worker-no-exit.ts");

test("docs-http-server.ts", () => {
  expect([path.join(import.meta.dir, "docs-http-server.ts")]).toRun();
});
test("worker-no-exit-http.ts", () => {
  expect([path.join(import.meta.dir, "worker-no-exit-http.ts")]).toRun();
});