import { LightningElement, api } from "lwc";

const DEFAULT_TITLE = "Binance Market Analysis";

export default class AgentRichOutput extends LightningElement {
  _structuredAgentResponse;
  _agentResponse;
  contentBlocks = [];
  rawResponse = "";

  @api title = DEFAULT_TITLE;
  @api subtitle = "";
  @api showRawResponse = false;

  @api
  get structuredAgentResponse() {
    return this._structuredAgentResponse;
  }

  set structuredAgentResponse(value) {
    this._structuredAgentResponse = value;
    if (this.hasValue(value)) {
      this.processResponse(value);
    }
  }

  @api
  get agentResponse() {
    return this._agentResponse;
  }

  set agentResponse(value) {
    this._agentResponse = value;
    if (this.hasValue(value)) {
      this.processResponse(value);
    }
  }

  get displayTitle() {
    return this.title || DEFAULT_TITLE;
  }

  get hasContent() {
    return this.contentBlocks.length > 0;
  }

  processResponse(value) {
    const parsed = this.parseValue(value);
    this.rawResponse = this.toDisplayString(parsed ?? value);
    const message = this.findMessage(parsed ?? value);
    this.contentBlocks = message ? this.buildBlocks(message) : [];
  }

  hasValue(value) {
    return value !== null && value !== undefined && value !== "";
  }

  parseValue(value) {
    if (value === null || value === undefined || value === "") {
      return null;
    }

    if (typeof value !== "string") {
      return value;
    }

    const trimmed = value.trim();
    if (!trimmed) {
      return null;
    }

    try {
      return JSON.parse(trimmed);
    } catch {
      return trimmed;
    }
  }

  findMessage(value) {
    if (typeof value === "string") {
      return value;
    }

    if (Array.isArray(value)) {
      return value
        .map((item) => this.findMessage(item))
        .filter(Boolean)
        .join("\n\n");
    }

    if (!value || typeof value !== "object") {
      return value === null || value === undefined ? "" : String(value);
    }

    const preferredKeys = [
      "message",
      "agentResponse",
      "response",
      "text",
      "content",
      "result",
      "value"
    ];

    for (const key of preferredKeys) {
      if (Object.prototype.hasOwnProperty.call(value, key)) {
        const message = this.findMessage(value[key]);
        if (message) {
          return message;
        }
      }
    }

    return this.toDisplayString(value);
  }

  buildBlocks(value) {
    const lines = String(value).replace(/\\n/g, "\n").split(/\r?\n/);
    const blocks = [];
    let index = 0;
    const sectionHeadings = new Set([
      "Symbol & Overview",
      "Price Movement",
      "Volume Analysis",
      "Bid/Ask Spread",
      "Session Timing",
      "Market Insights",
      "Profit/Loss Scenarios & Next Steps",
      "Recommendations"
    ]);

    lines.forEach((line) => {
      const trimmed = line.trim();

      if (!trimmed) {
        return;
      }

      index += 1;
      const key = `block-${index}`;
      const markdownHeading = trimmed.match(/^#{1,3}\s+(.+)$/);

      if (markdownHeading) {
        blocks.push({
          key,
          text: this.plainText(markdownHeading[1]),
          isTitle: true
        });
        return;
      }

      if (
        /Market Report$/i.test(trimmed) &&
        !/^Market Analysis Report/i.test(trimmed)
      ) {
        const pair = trimmed.split(/\s+/)[0];
        blocks.push({
          key,
          text: this.plainText(trimmed),
          badge: pair.slice(0, 3),
          isPair: true
        });
        return;
      }

      const sectionText = trimmed.replace(/^[-*•]\s+/, "");
      if (sectionHeadings.has(sectionText)) {
        blocks.push({ key, text: sectionText, isSection: true });
        return;
      }

      const metric = trimmed.match(/^\*\*([^*]+?):\*\*\s*(.*)$/);
      if (metric) {
        blocks.push({
          key,
          label: this.plainText(metric[1]),
          value: this.plainText(metric[2]),
          isMetric: true
        });
        return;
      }

      if (/^Price Range Visualization/i.test(trimmed)) {
        blocks.push({ key, text: trimmed, isChartLabel: true });
        return;
      }

      if (/[─═]{2,}/.test(trimmed)) {
        blocks.push({ key, text: trimmed, isChart: true });
        return;
      }

      const text = this.plainText(trimmed.replace(/^[-*•]\s+/, ""));
      if (/^Would you like/i.test(text)) {
        blocks.push({ key, text, isQuestion: true });
      } else if (
        /^(For profit|Consider |Look for |Use stop-loss|Monitor )/i.test(text)
      ) {
        blocks.push({ key, text, isInsight: true });
      } else {
        blocks.push({ key, text, isParagraph: true });
      }
    });

    return blocks;
  }

  plainText(value) {
    return String(value)
      .replace(/\*\*(.+?)\*\*/g, "$1")
      .replace(/__(.+?)__/g, "$1")
      .replace(/`([^`]+)`/g, "$1");
  }

  toDisplayString(value) {
    if (typeof value === "string") {
      return value;
    }

    try {
      return JSON.stringify(value, null, 2);
    } catch {
      return String(value ?? "");
    }
  }
}
