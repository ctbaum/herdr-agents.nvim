import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const { IdeClient } = await import(pathToFileURL(`${process.env.PI_IDE_EXTENSION_PATH}/client.ts`).href);
const lock = JSON.parse(await readFile(process.env.PI_IDE_TEST_LOCK, "utf8"));
lock.port = Number(process.env.PI_IDE_TEST_PORT);
const invalid = new IdeClient({ ...lock, authToken: "incorrect-authentication-token" });
await assert.rejects(invalid.connect());
invalid.close();
const client = new IdeClient(lock);
await client.connect();
try {
  const tabs = await client.callTool("getOpenEditorTabs", {});
  assert.match(JSON.stringify(tabs), /pi-ide-test\.txt/);
  const diagnostics = await client.callTool("getDiagnostics", {});
  assert.match(JSON.stringify(diagnostics), /protocol diagnostic/);
  for (const [action, expected] of [["accept", "FILE_SAVED"], ["reject", "DIFF_REJECTED"]]) {
    const result = await client.callTool("openDiff", {
      old_file_path: process.env.PI_IDE_TEST_FILE,
      new_file_path: process.env.PI_IDE_TEST_FILE,
      new_file_contents: `${action}\n`,
      tab_name: `test-${action}`,
    });
    assert.equal(result.content[0].text, expected);
    if (action === "accept") assert.equal(result.content[1].text, "accept\n");
    await client.callTool("close_tab", { tab_name: `test-${action}` });
  }
  assert.equal(await readFile(process.env.PI_IDE_TEST_FILE, "utf8"), "original\n");
  console.log("Pi IDE authenticated handshake, diagnostics, buffers, accept/reject: passed");
} finally {
  client.close();
}
