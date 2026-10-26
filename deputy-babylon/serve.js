// Мини-сервер статики для дев-тестов: node serve.js [порт]
// POST /__save__ — запись раскладки карты в data/city_layout.json (для редактора).
import { createServer } from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const root = new URL(".", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".svg": "image/svg+xml" };
const port = Number(process.argv[2] ?? 8137);

const ALLOWED = new Set(["city_layout.json"]);

createServer(async (req, res) => {
  let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (req.method === "POST" && p === "/__save__") {
    let body = "";
    for await (const chunk of req) body += chunk;
    try {
      const parsed = JSON.parse(body);
      const file = String(parsed?.file ?? "");
      if (!ALLOWED.has(file) || !parsed?.data) throw new Error("bad payload");
      await writeFile(join(root, "data", file), JSON.stringify(parsed.data, null, 2), "utf8");
      res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
      res.end(JSON.stringify({ ok: true, file }));
    } catch (e) {
      res.writeHead(400, { "Content-Type": "application/json", "Cache-Control": "no-store" });
      res.end(JSON.stringify({ ok: false, error: String(e && e.message ? e.message : e) }));
    }
    return;
  }
  if (p === "/") p = "/index.html";
  try {
    const file = normalize(join(root, p));
    const data = await readFile(file);
    res.writeHead(200, { "Content-Type": types[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-store" });
    res.end(data);
  } catch {
    res.writeHead(404); res.end("no");
  }
}).listen(port, () => console.log(`http://localhost:${port}`));
