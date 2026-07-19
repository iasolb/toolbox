# myToolBox

Personal utility toolbox. Each tool is a self-contained subfolder; one clone
brings the whole kit onto a new machine.

| Tool | What it does |
| --- | --- |
| [machine-sync](machine-sync/README.md) | Peer-to-peer file transfer between the Mac and the PC (`pull.mac`/`push.mac` on the PC, `pull.pc`/`push.pc` on the Mac, plus `*.claude` variants targeting the claude working dir) |
| [csv-utf8](csv-utf8/README.md) | Rewrites non-UTF-8 CSVs as UTF-8 in place; also backs machine-sync's `--csv` flag |
| [StayinAlive.ps1](StayinAlive.ps1) | Keeps the PC awake |
