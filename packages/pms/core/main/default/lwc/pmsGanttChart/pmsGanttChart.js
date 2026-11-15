import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getGantt from "@salesforce/apex/PMS_UIController.getGantt";
import updateTaskDates from "@salesforce/apex/PMS_UIController.updateTaskDates";
import { addDays, daysBetween, todayIso, errorMessage } from "c/pmsDateUtils";

/** Project Gantt: tasks and milestones on a timeline, with progress and a today marker. */
export default class PmsGanttChart extends NavigationMixin(LightningElement) {
  @api recordId;

  data;
  loading = false;
  error;
  editing;
  editStart;
  editEnd;

  connectedCallback() {
    this.load();
  }

  async load() {
    if (!this.recordId) {
      return;
    }
    this.loading = true;
    this.error = undefined;
    try {
      this.data = await getGantt({ projectId: this.recordId });
    } catch (e) {
      this.error = errorMessage(e);
    } finally {
      this.loading = false;
    }
  }

  get title() {
    return this.data ? `Timeline · ${this.data.projectName}` : "Timeline";
  }
  get hasTasks() {
    return this.data && this.data.tasks.length > 0;
  }
  get range() {
    const start =
      this.data && this.data.projectStart
        ? addDays(this.data.projectStart, -2)
        : addDays(todayIso(), -7);
    const end =
      this.data && this.data.projectEnd
        ? addDays(this.data.projectEnd, 3)
        : addDays(todayIso(), 30);
    return { start, end, days: Math.max(7, daysBetween(start, end)) };
  }

  /** Month or week markers across the top, as % positions. */
  get scale() {
    const { start, days } = this.range;
    const weekly = days > 120;
    const marks = [];
    for (let i = 0; i <= days; i++) {
      const iso = addDays(start, i);
      const isMonthStart = iso.substring(8, 10) === "01";
      const isMonday = new Date(iso + "T00:00:00Z").getUTCDay() === 1;
      if ((weekly && isMonthStart) || (!weekly && (isMonday || i === 0))) {
        marks.push({
          key: iso,
          label: weekly ? iso.substring(0, 7) : iso.substring(5),
          style: `left:${((i / days) * 100).toFixed(2)}%`
        });
      }
    }
    return marks;
  }

  get todayStyle() {
    const { start, days } = this.range;
    const pos = daysBetween(start, todayIso());
    if (pos < 0 || pos > days) {
      return "display:none";
    }
    return `left:${((pos / days) * 100).toFixed(2)}%`;
  }

  get rows() {
    if (!this.data) {
      return [];
    }
    const { start, days } = this.range;
    const names = {};
    this.data.tasks.forEach((t) => (names[t.id] = t.name));
    const children = {};
    this.data.tasks.forEach((t) => {
      if (t.parentId) {
        children[t.parentId] = (children[t.parentId] || 0) + 1;
      }
    });
    return this.data.tasks.map((t) => {
      const s = t.startDate || t.endDate;
      const e = t.endDate || t.startDate;
      const hasDates = !!s;
      const left = hasDates ? (daysBetween(start, s) / days) * 100 : 0;
      const width = hasDates
        ? (Math.max(1, daysBetween(s, e) + 1) / days) * 100
        : 0;
      const pct = t.percentComplete
        ? Math.min(100, Number(t.percentComplete))
        : 0;
      const late = !t.isMilestone && e && e < todayIso() && t.status !== "Done";
      let barCls = "pms-bar";
      if (late) {
        barCls += " pms-late";
      } else if (t.status === "Done") {
        barCls += " pms-done";
      } else if (t.status === "Blocked") {
        barCls += " pms-blocked";
      }
      return {
        key: t.id,
        id: t.id,
        name: t.name,
        nameCls:
          (t.parentId ? "pms-name pms-indent" : "pms-name") +
          (children[t.id] ? " pms-summary" : ""),
        assignee: t.assignee,
        isMilestone: t.isMilestone,
        hasDates,
        startDate: s,
        endDate: e,
        barStyle: `left:${left.toFixed(2)}%;width:${width.toFixed(2)}%`,
        diamondStyle: `left:calc(${left.toFixed(2)}% - 6px)`,
        progressStyle: `width:${pct}%`,
        barCls,
        tooltip:
          `${t.name}: ${s || "?"} → ${e || "?"} · ${pct}%` +
          (t.predecessorId && names[t.predecessorId]
            ? ` · after ${names[t.predecessorId]}`
            : "") +
          (t.assignee ? ` · ${t.assignee}` : "")
      };
    });
  }

  open(e) {
    const id = e.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: id, actionName: "view" }
    });
  }

  startEdit(e) {
    const id = e.currentTarget.dataset.id;
    const row = this.rows.find((r) => r.id === id);
    if (!row || row.isMilestone) {
      return;
    }
    this.editing = row;
    this.editStart = row.startDate;
    this.editEnd = row.endDate;
  }
  handleEdit(e) {
    this[e.target.name] = e.detail.value;
  }
  cancelEdit() {
    this.editing = undefined;
  }
  async saveEdit() {
    this.loading = true;
    try {
      await updateTaskDates({
        taskId: this.editing.id,
        startDate: this.editStart,
        endDate: this.editEnd
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Task dates updated",
          variant: "success",
          message: ""
        })
      );
      this.editing = undefined;
      await this.load();
    } catch (err) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Could not update task",
          message: errorMessage(err),
          variant: "error"
        })
      );
      this.loading = false;
    }
  }
}
