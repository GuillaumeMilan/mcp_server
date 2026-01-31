/**
 * McpApp — lightweight, dependency-free helper for MCP App iframes.
 *
 * Wraps the postMessage JSON-RPC 2.0 protocol so you don't need the
 * @modelcontextprotocol/ext-apps npm package.
 *
 * Usage:
 *
 *   const app = new McpApp();
 *
 *   app.ontoolinput = (args) => renderArgs(args);
 *   app.ontoolresult = (result) => renderResult(result);
 *
 *   const { hostCapabilities, hostContext } = await app.connect();
 *
 *   // Later — call a server tool, send messages, etc.
 *   const result = await app.callServerTool("get_weather", { location: "NYC" });
 *   await app.sendMessage("assistant", { type: "text", text: "Done!" });
 */
class McpApp {
  constructor() {
    this._nextId = 1;
    this._pending = new Map(); // id -> { resolve, reject }
    this._listener = null;
    this._connected = false;

    // Callbacks — assign functions to handle incoming notifications
    this.ontoolinput = null;
    this.ontoolinputpartial = null;
    this.ontoolresult = null;
    this.ontoolcancelled = null;
    this.onhostcontextchanged = null;
    this.onteardown = null;
  }

  /**
   * Initiate the initialization handshake.
   *
   * Sends ui/initialize, waits for the host response, then sends
   * ui/notifications/initialized.
   *
   * @param {object} [appCapabilities={}] - Capabilities to advertise.
   * @returns {Promise<{hostCapabilities: object, hostContext: object}>}
   */
  connect(appCapabilities) {
    if (this._connected) {
      return Promise.reject(new Error("Already connected"));
    }

    this._installListener();

    return this._sendRequest("ui/initialize", {
      appCapabilities: appCapabilities || {},
    }).then(function (result) {
      this._connected = true;

      // Send the initialized notification (no id — it's a notification)
      this._postMessage({
        jsonrpc: "2.0",
        method: "ui/notifications/initialized",
        params: {},
      });

      return {
        hostCapabilities: result.hostCapabilities,
        hostContext: result.hostContext,
      };
    }.bind(this));
  }

  /**
   * Call a server-side MCP tool through the host.
   *
   * @param {string} name - Tool name.
   * @param {object} [args={}] - Tool arguments.
   * @returns {Promise<object>} Tool result.
   */
  callServerTool(name, args) {
    return this._sendRequest("tools/call", {
      name: name,
      arguments: args || {},
    });
  }

  /**
   * Send a message to the host chat.
   *
   * @param {string} role - Message role ("user" or "assistant").
   * @param {object} content - Message content object.
   * @returns {Promise<object>}
   */
  sendMessage(role, content) {
    return this._sendRequest("ui/message", {
      role: role,
      content: content,
    });
  }

  /**
   * Update the model context seen by the LLM in future turns.
   *
   * @param {Array|null} content - Content items for the model.
   * @param {object|null} structuredContent - Structured data (not in model context).
   * @returns {Promise<object>}
   */
  updateModelContext(content, structuredContent) {
    var params = {};
    if (content != null) params.content = content;
    if (structuredContent != null) params.structuredContent = structuredContent;
    return this._sendRequest("ui/update-model-context", params);
  }

  /**
   * Ask the host to open a URL.
   *
   * @param {string} url - The URL to open.
   * @returns {Promise<object>}
   */
  openLink(url) {
    return this._sendRequest("ui/open-link", { url: url });
  }

  /**
   * Request a display mode change (e.g., "fullscreen", "pip", "inline").
   *
   * @param {string} mode - Desired display mode.
   * @returns {Promise<{mode: string}>} The actual mode set by the host.
   */
  requestDisplayMode(mode) {
    return this._sendRequest("ui/request-display-mode", { mode: mode });
  }

  /**
   * Report a size change to the host.
   *
   * @param {number} width
   * @param {number} height
   */
  reportSizeChanged(width, height) {
    this._postMessage({
      jsonrpc: "2.0",
      method: "ui/notifications/size-changed",
      params: { width: width, height: height },
    });
  }

  /**
   * Disconnect and remove the message listener.
   */
  disconnect() {
    if (this._listener) {
      window.removeEventListener("message", this._listener);
      this._listener = null;
    }
    this._connected = false;

    // Reject all pending requests
    this._pending.forEach(function (entry) {
      entry.reject(new Error("Disconnected"));
    });
    this._pending.clear();
  }

  // ── Internal ──────────────────────────────────────────────────────

  _installListener() {
    if (this._listener) return;

    this._listener = this._onMessage.bind(this);
    window.addEventListener("message", this._listener);
  }

  _onMessage(event) {
    var data = event.data;
    if (!data || typeof data !== "object" || data.jsonrpc !== "2.0") return;

    // Response to a pending request
    if (data.id != null && (data.result !== undefined || data.error !== undefined)) {
      var entry = this._pending.get(data.id);
      if (entry) {
        this._pending.delete(data.id);
        if (data.error) {
          var err = new Error(data.error.message || "JSON-RPC error");
          err.code = data.error.code;
          err.data = data.error.data;
          entry.reject(err);
        } else {
          entry.resolve(data.result);
        }
      }
      return;
    }

    // Incoming notification or request from host
    var method = data.method;
    var params = data.params || {};

    switch (method) {
      case "ui/notifications/tool-input":
        if (this.ontoolinput) this.ontoolinput(params.arguments);
        break;

      case "ui/notifications/tool-input-partial":
        if (this.ontoolinputpartial) this.ontoolinputpartial(params.arguments);
        break;

      case "ui/notifications/tool-result":
        if (this.ontoolresult) this.ontoolresult(params);
        break;

      case "ui/notifications/tool-cancelled":
        if (this.ontoolcancelled) this.ontoolcancelled(params.reason);
        break;

      case "ui/notifications/host-context-changed":
        if (this.onhostcontextchanged) this.onhostcontextchanged(params);
        break;

      case "ui/resource-teardown":
        if (this.onteardown) this.onteardown(params.reason);
        // Respond to the teardown request
        if (data.id != null) {
          this._postMessage({
            jsonrpc: "2.0",
            result: {},
            id: data.id,
          });
        }
        break;
    }
  }

  _sendRequest(method, params) {
    var id = this._nextId++;
    var self = this;

    return new Promise(function (resolve, reject) {
      self._pending.set(id, { resolve: resolve, reject: reject });
      self._postMessage({
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: id,
      });
    });
  }

  _postMessage(msg) {
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(msg, "*");
    }
  }
}

// Export for both module and script-tag usage
if (typeof module !== "undefined" && module.exports) {
  module.exports = McpApp;
}
