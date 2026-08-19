import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";
import * as path from "path";
import * as fs from "fs";

export default function hook(pi: HookAPI): void {
  pi.on("tool_call", async (event, ctx) => {
    try {
      // 1. Detect if it's the main orchestrator session.
      // The main session file is stored directly in the session directory.
      // Subagent session files are stored in a subdirectory named after the main session's ID.
      const sessionFile = ctx.sessionManager.getSessionFile();
      const sessionDir = ctx.sessionManager.getSessionDir();
      const isMainSession = path.dirname(sessionFile) === sessionDir;

      if (!isMainSession) {
        return; // No-op for subagents
      }

      // 2. Block web fetch/search tools
      if (event.toolName === "web_search") {
        return {
          block: true,
          reason: "Direct web search from the main orchestrator is blocked. Dispatch the 'fetch' subagent instead."
        };
      }

      if (event.toolName === "read") {
        const targetPath = String(event.input?.path || "");
        
        // Block web fetch
        if (targetPath.startsWith("http://") || targetPath.startsWith("https://") || targetPath.startsWith("www.")) {
          return {
            block: true,
            reason: "Direct web fetch from the main orchestrator is blocked. Dispatch the 'fetch' subagent instead."
          };
        }

        // 3. Block whole-file reads > 400 lines
        // A whole-file read has no line selector (e.g., :10-20). We check for a colon followed by numbers.
        const hasLineSelector = /:\d+/.test(targetPath);
        
        if (!hasLineSelector) {
          // Resolve the path to count lines, ignoring internal schemes.
          if (targetPath.includes("://")) {
             return; // Skip internal URIs like skill://, memory://
          }
          
          // Remove any non-line selectors like :raw just to find the actual file path
          const cleanPath = targetPath.replace(/:[a-zA-Z]+(-[a-zA-Z]+)*$/, '');
          const absPath = path.resolve(ctx.cwd, cleanPath);
          
          try {
             const stat = fs.statSync(absPath);
             if (stat.isFile()) {
                // Skip line count for files > 2MB to avoid blocking the event loop or OOM
                if (stat.size > 2 * 1024 * 1024) {
                   return;
                }
                // Count lines efficiently
                const content = fs.readFileSync(absPath, 'utf8');
                let lineCount = 0;
                for (let i = 0; i < content.length; i++) {
                   if (content[i] === '\n') lineCount++;
                }
                
                // The ~50-line rule in the prose is a judgement bright line for the architect.
                // This hook is the deliberately looser hard backstop, set high enough that 
                // ordinary verification reads are never blocked.
                if (lineCount > 200) {
                   return {
                      block: true,
                      reason: `File '${targetPath}' has ${lineCount} lines. Whole-file reads >200 lines from the main orchestrator are blocked. Narrow the range with grep/lsp first, or dispatch 'scout' to investigate.`
                   };
                }
             }
          } catch (e) {
             // File might not exist or is unreadable; fail open and let the read tool handle it.
             return;
          }
        }
      }

    } catch (error) {
      // Fail OPEN on any internal error
      return;
    }
  });
}
