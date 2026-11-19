/* STUDY productivity add-on. Loaded before the role-specific portal boot sequence. */
(function () {
  const role = PORTAL;
  const featurePages = role === "student"
    ? [["saved", "Saved papers"], ["planner", "Study planner"], ["calendar", "Exam calendar"], ["announcements", "Announcements"]]
    : [["calendar", "Exam calendar"], ["announcements", "Announcements"]];
  let notices = [], noticeReads = [], savedPaperIds = [], tasks = [];

  const originalRefresh = refresh;
  refresh = async function () {
    await originalRefresh();
    try {
      const [a, r] = await Promise.all([
        db.from("announcements").select("*").order("is_pinned", { ascending: false }).order("created_at", { ascending: false }),
        db.from("announcement_reads").select("announcement_id").eq("user_id", user.id)
      ]);
      if (a.error) throw a.error;
      if (r.error) throw r.error;
      notices = a.data || [];
      noticeReads = r.data || [];
      if (role === "student") {
        const [b, t] = await Promise.all([
          db.from("paper_bookmarks").select("paper_id").eq("user_id", user.id),
          db.from("study_tasks").select("*").order("is_completed", { ascending: true }).order("due_at", { ascending: true })
        ]);
        if (b.error) throw b.error;
        if (t.error) throw t.error;
        savedPaperIds = (b.data || []).map(x => x.paper_id);
        tasks = t.data || [];
      }
    } catch (error) {
      console.error("STUDY productivity data:", error.message || error);
      notices = notices || []; noticeReads = noticeReads || [];
    }
  };

  const originalPaperCard = paperCard;
  paperCard = function (paper, isTeacher) {
    let html = originalPaperCard(paper, isTeacher);
    if (role === "student") {
      const button = '<button class="btn feature-save ' + (savedPaperIds.includes(paper.id) ? "saved" : "") + '" data-feature-bookmark="' + paper.id + '">' +
        (savedPaperIds.includes(paper.id) ? "★ Saved" : "☆ Save") + '</button>';
      html = html.replace(/(<button class="btn" data-open="[^"]+">View PDF<\/button>)/, "$1" + button);
    }
    return html;
  };

  const originalBindPaperActions = bindPaperActions;
  bindPaperActions = function (isTeacher) {
    originalBindPaperActions(isTeacher);
    document.querySelectorAll("[data-feature-bookmark]").forEach(b => b.onclick = () => toggleBookmark(b.dataset.featureBookmark));
  };

  const originalNav = nav;
  nav = function () {
    originalNav();
    const host = el("nav");
    featurePages.forEach(([key, label]) => {
      const b = document.createElement("button");
      b.dataset.featurePage = key; b.textContent = label; b.className = page === key ? "active" : "";
      if (key === "announcements") {
        const unread = notices.filter(a => !noticeReads.some(r => r.announcement_id === a.id)).length;
        if (unread) b.textContent += " · " + unread;
      }
      if (key === "saved" && savedPaperIds.length) b.textContent += " · " + savedPaperIds.length;
      b.onclick = () => { page = key; render(); };
      host.appendChild(b);
    });
  };

  function introFeature(title, description) {
    return '<div class="welcome"><div><div class="eyebrow">STUDY WORKSPACE</div><h1>' + safe(title) + '</h1><p>' + safe(description) + '</p></div></div>';
  }
  function emptyFeature(title, description) { return '<div class="empty"><b>' + safe(title) + '</b>' + safe(description) + '</div>'; }

  function announcementPage() {
    const read = new Set(noticeReads.map(x => x.announcement_id));
    return introFeature("Announcements", "Important updates and notices from your school.") +
      (notices.length ? notices.map(a =>
        '<article class="card announcement-card ' + (a.is_pinned ? "pinned" : "") + '">' +
        '<div class="cardhead"><div><span class="eyebrow">' + (a.is_pinned ? "PINNED NOTICE" : "SCHOOL NOTICE") + '</span><h3>' + safe(a.title) + '</h3></div>' +
        '<span class="tag">' + (read.has(a.id) ? "READ" : "NEW") + '</span></div>' +
        '<p>' + safe(a.message).replace(/\n/g, "<br>") + '</p><div class="meta">' + new Date(a.created_at).toLocaleString() +
        (a.expires_at ? " · Expires " + new Date(a.expires_at).toLocaleString() : "") + '</div>' +
        (!read.has(a.id) ? '<div class="actions"><button class="btn primary" data-feature-read="' + a.id + '">Mark as read</button></div>' : '') +
        '</article>'
      ).join("") : emptyFeature("You are all caught up", "New school announcements will appear here."));
  }
  function calendarPage() {
    const now = Date.now();
    const items = papers.filter(p =>
      (p.due_at && new Date(p.due_at).getTime() > now) ||
      (p.available_from && new Date(p.available_from).getTime() > now)
    ).sort((a, b) => new Date(a.available_from || a.due_at) - new Date(b.available_from || b.due_at));
    return introFeature("Exam calendar", "Upcoming exam releases and submission deadlines.") +
      (items.length ? '<div class="calendar-list">' + items.map(p => {
        const date = new Date(p.available_from || p.due_at);
        const openTime = p.available_from && new Date(p.available_from).getTime() > now;
        return '<article class="card calendar-item"><div class="calendar-date"><b>' + date.toLocaleDateString(undefined, { day: "2-digit" }) +
          '</b><span>' + date.toLocaleDateString(undefined, { month: "short" }) + '</span></div><div class="calendar-info"><h3>' + safe(p.title) +
          '</h3><div class="meta">' + safe(p.subject || "General") + ' · ' + safe(p.target_class || "All classes") + '</div><div class="meta">' +
          (openTime ? "Opens: " + date.toLocaleString() : "Deadline: " + (p.due_at ? new Date(p.due_at).toLocaleString() : "Not set")) +
          '</div></div><span class="tag">' + (p.status || "published").toUpperCase() + '</span></article>';
      }).join("") + '</div>' : emptyFeature("No upcoming dates", "Exam schedules and deadlines will appear here."));
  }
  function savedPage() {
    const saved = papers.filter(p => savedPaperIds.includes(p.id));
    return introFeature("Saved papers", "Your bookmarked question papers, ready for revision.") +
      (saved.length ? saved.map(p => paperCard(p, false)).join("") : emptyFeature("No saved papers", "Use the ☆ Save button on a paper to keep it here."));
  }
  function plannerPage() {
    const pending = tasks.filter(t => !t.is_completed), complete = tasks.filter(t => t.is_completed);
    const taskCard = t => {
      const related = t.paper_id ? papers.find(p => p.id === t.paper_id) : null;
      const late = !t.is_completed && t.due_at && new Date(t.due_at).getTime() < Date.now();
      return '<article class="card task-card"><label class="task-check"><input type="checkbox" data-feature-task="' + t.id + '" ' +
        (t.is_completed ? "checked" : "") + '><span><b>' + safe(t.title) + '</b><span class="meta">' + safe(t.details || "") +
        '</span><span class="meta">' + (t.due_at ? "Due " + new Date(t.due_at).toLocaleString() : "No due date") +
        (related ? " · " + safe(related.title) : "") + '</span></span></label>' +
        (late ? '<span class="status">OVERDUE</span>' : '') + '<button class="btn" data-feature-delete-task="' + t.id + '">Delete</button></article>';
    };
    return introFeature("Study planner", "Break revision into smaller tasks and keep track of your progress.") +
      '<div class="card"><form id="featureTaskForm"><label for="featureTaskTitle">Study task</label><input id="featureTaskTitle" maxlength="160" required placeholder="Revise quadratic equations">' +
      '<div class="fieldrow"><div><label for="featureTaskDue">Due date (optional)</label><input id="featureTaskDue" type="datetime-local"></div><div><label for="featureTaskPaper">Related exam (optional)</label><select id="featureTaskPaper"><option value="">No linked exam</option>' +
      papers.map(p => '<option value="' + p.id + '">' + safe(p.title) + '</option>').join("") + '</select></div></div>' +
      '<label for="featureTaskDetails">Notes</label><textarea id="featureTaskDetails" rows="2" maxlength="1000" placeholder="Chapters, exercise numbers or reminders…"></textarea>' +
      '<div class="actions"><button class="btn primary">＋ Add task</button></div></form></div>' +
      '<div class="section"><h3>To do · ' + pending.length + '</h3></div>' + (pending.length ? pending.map(taskCard).join("") : emptyFeature("Nothing pending", "Add a task to build your revision plan.")) +
      '<div class="section"><h3>Completed · ' + complete.length + '</h3></div>' + (complete.length ? complete.map(taskCard).join("") : '<p class="meta">Completed tasks will be kept here.</p>');
  }

  async function toggleBookmark(id) {
    const saved = savedPaperIds.includes(id);
    const result = saved
      ? await db.from("paper_bookmarks").delete().eq("user_id", user.id).eq("paper_id", id)
      : await db.from("paper_bookmarks").insert({ user_id: user.id, paper_id: id });
    if (result.error) { alert(result.error.message); return; }
    savedPaperIds = saved ? savedPaperIds.filter(x => x !== id) : [...savedPaperIds, id];
    render();
  }
  async function markRead(id) {
    const { error } = await db.from("announcement_reads").insert({ announcement_id: id, user_id: user.id });
    if (error && error.code !== "23505") { alert(error.message); return; }
    noticeReads.push({ announcement_id: id }); render();
  }
  async function createTask(event) {
    event.preventDefault();
    const title = el("featureTaskTitle").value.trim(), details = el("featureTaskDetails").value.trim();
    const due = el("featureTaskDue").value ? new Date(el("featureTaskDue").value).toISOString() : null;
    const paper = el("featureTaskPaper").value || null;
    if (title.length < 2) { alert("Enter a task name."); return; }
    const button = el("featureTaskForm").querySelector("button"); button.disabled = true;
    try {
      const { data, error } = await db.from("study_tasks").insert({ student_id: user.id, title, details, due_at: due, paper_id: paper }).select("*").single();
      if (error) throw error;
      tasks.unshift(data); render();
    } catch (error) { alert(error.message || "Could not save the task."); }
    finally { const b = el("featureTaskForm")?.querySelector("button"); if (b) b.disabled = false; }
  }
  async function toggleTask(id, checked) {
    const { error } = await db.from("study_tasks").update({ is_completed: checked, completed_at: checked ? new Date().toISOString() : null }).eq("id", id);
    if (error) { alert(error.message); return; }
    const task = tasks.find(x => x.id === id);
    if (task) { task.is_completed = checked; task.completed_at = checked ? new Date().toISOString() : null; }
    render();
  }
  async function deleteTask(id) {
    if (!confirm("Delete this study task?")) return;
    const { error } = await db.from("study_tasks").delete().eq("id", id);
    if (error) { alert(error.message); return; }
    tasks = tasks.filter(x => x.id !== id); render();
  }
  function exportGradebook() {
    const rows = [["Student name", "Registration number", "Paper", "Subject", "Submitted at", "Status", "Marks", "Maximum marks", "Percentage", "Remarks"]];
    subs.forEach(s => {
      const p = papers.find(x => x.id === s.paper_id), student = studentProfiles.find(x => x.id === s.student_id);
      const max = Number(s.max_marks || p?.max_marks || 0), marks = s.marks_awarded === null ? null : Number(s.marks_awarded);
      rows.push([student?.full_name || "Student", student?.registration_number || "", p?.title || "Exam", p?.subject || "",
        s.submitted_at, s.status, marks ?? "", max || "", marks !== null && max ? Math.round(marks / max * 100) + "%" : "", s.remarks || ""]);
    });
    const csv = rows.map(row => row.map(v => '"' + String(v ?? "").replace(/"/g, '""') + '"').join(",")).join("\r\n");
    const blob = new Blob(["\ufeff", csv], { type: "text/csv;charset=utf-8" }), url = URL.createObjectURL(blob), a = document.createElement("a");
    a.href = url; a.download = "study-gradebook.csv"; document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url);
  }

  const originalPaperCard = paperCard;
  paperCard = function (p, isTeacher) {
    let html = originalPaperCard(p, isTeacher);
    if (role === "student") {
      const button = '<button class="btn ' + (savedPaperIds.includes(p.id) ? "saved" : "") + '" data-feature-bookmark="' + p.id + '">' +
        (savedPaperIds.includes(p.id) ? "★ Saved" : "☆ Save") + '</button>';
      html = html.replace(/(<button class="btn" data-open="[^"]+">View PDF<\/button>)/, "$1" + button);
    }
    return html;
  };
  const originalBindPaperActions = bindPaperActions;
  bindPaperActions = function (isTeacher) {
    originalBindPaperActions(isTeacher);
    document.querySelectorAll("[data-feature-bookmark]").forEach(b => b.onclick = () => toggleBookmark(b.dataset.featureBookmark));
  };
  const originalNav = nav;
  nav = function () {
    originalNav();
    featurePages.forEach(([key, label]) => {
      const b = document.createElement("button"); b.dataset.featurePage = key; b.textContent = label; b.className = page === key ? "active" : "";
      if (key === "announcements") { const n = notices.filter(a => !noticeReads.some(r => r.announcement_id === a.id)).length; if (n) b.textContent += " · " + n; }
      if (key === "saved" && savedPaperIds.length) b.textContent += " · " + savedPaperIds.length;
      b.onclick = () => { page = key; render(); };
      el("nav").appendChild(b);
    });
  };
  const originalRender = render;
  render = function () {
    originalRender();
    if (page === "saved") { el("pageTitle").textContent = "Saved papers"; el("page").innerHTML = savedPage(); }
    else if (page === "planner") { el("pageTitle").textContent = "Study planner"; el("page").innerHTML = plannerPage(); }
    else if (page === "calendar") { el("pageTitle").textContent = "Exam calendar"; el("page").innerHTML = calendarPage(); }
    else if (page === "announcements") { el("pageTitle").textContent = "Announcements"; el("page").innerHTML = announcementPage(); }
    if (["saved","planner","calendar","announcements"].includes(page)) {
      document.querySelectorAll("[data-open]").forEach(b => b.onclick = () => { const p = papers.find(x => x.id === b.dataset.open); if (p) openFile("paper-pdfs", p.pdf_path); });
      document.querySelectorAll("[data-feature-bookmark]").forEach(b => b.onclick = () => toggleBookmark(b.dataset.featureBookmark));
      document.querySelectorAll("[data-feature-read]").forEach(b => b.onclick = () => markRead(b.dataset.featureRead));
      if (el("featureTaskForm")) el("featureTaskForm").onsubmit = createTask;
      document.querySelectorAll("[data-feature-task]").forEach(b => b.onchange = () => toggleTask(b.dataset.featureTask, b.checked));
      document.querySelectorAll("[data-feature-delete-task]").forEach(b => b.onclick = () => deleteTask(b.dataset.featureDeleteTask));
    }
    if (page === "submissions") {
      const host = el("page");
      if (!el("exportGradebook")) {
        const bar = document.createElement("div"); bar.className = "card filter-card";
        bar.innerHTML = '<div class="fieldrow"><div><label for="featureReviewFilter">Review queue</label><select id="featureReviewFilter"><option value="all">All submissions</option><option value="submitted">Awaiting review</option><option value="returned">Returned</option><option value="reviewed">Reviewed</option></select></div><div><label>Export</label><button class="btn" id="exportGradebook">Download gradebook CSV</button></div></div>';
        host.prepend(bar); el("exportGradebook").onclick = exportGradebook;
        el("featureReviewFilter").onchange = () => {
          const value = el("featureReviewFilter").value;
          host.querySelectorAll("article.card").forEach(card => {
            if (card === bar) return;
            const badge = card.querySelector(".status");
            card.style.display = !badge || value === "all" || badge.textContent.trim() === value ? "" : "none";
          });
        };
      }
    }
    if (page === "overview") {
      const unread = notices.filter(a => !noticeReads.some(r => r.announcement_id === a.id)).length;
      const pending = subs.filter(s => s.status === "submitted").length;
      const panel = document.createElement("div"); panel.className = "card feature-pulse";
      panel.innerHTML = '<div class="section"><h3>Workspace pulse</h3><span class="tag">LIVE SUMMARY</span></div><div class="pulse-grid">' +
        '<div><b>' + (role === "student" ? savedPaperIds.length : pending) + '</b><span>' + (role === "student" ? "Saved papers" : "Awaiting review") + '</span></div>' +
        '<div><b>' + unread + '</b><span>Unread notices</span></div>' +
        '<div><b>' + (role === "student" ? tasks.filter(t => !t.is_completed).length : papers.filter(p => p.due_at && new Date(p.due_at) > new Date()).length) + '</b><span>' + (role === "student" ? "Open study tasks" : "Upcoming deadlines") + '</span></div></div>';
      el("page").appendChild(panel);
    }
  };
  boot();
})();