/* STUDY admin announcement manager. */
(function () {
  let adminAnnouncements = [];
  const originalLoad = loadData;
  loadData = async function () {
    await originalLoad();
    const { data, error } = await db.from("announcements").select("*").order("created_at", { ascending: false });
    if (error) throw error;
    adminAnnouncements = data || [];
  };
  const originalNav = nav;
  nav = function () {
    originalNav();
    const b = document.createElement("button"); b.textContent = "Announcements";
    b.className = page === "announcements" ? "active" : ""; b.dataset.page = "announcements";
    b.onclick = () => { page = "announcements"; render(); }; el("nav").appendChild(b);
  };
  function renderAnnouncementManager() {
    const rows = adminAnnouncements.map(a =>
      '<article class="card announcement-card ' + (a.is_pinned ? "pinned" : "") + '">' +
      '<div class="cardhead"><div><span class="eyebrow">' + safe(a.audience.toUpperCase()) + (a.target_class ? " · " + safe(a.target_class) : "") + '</span><h3>' + safe(a.title) + '</h3></div>' +
      '<span class="tag">' + (a.is_pinned ? "PINNED" : "NOTICE") + '</span></div><p>' + safe(a.message).replace(/\n/g, "<br>") + '</p>' +
      '<div class="meta">Starts ' + when(a.starts_at) + (a.expires_at ? " · Expires " + when(a.expires_at) : "") + '</div>' +
      '<div class="actions"><button class="btn" data-pin-notice="' + a.id + '">' + (a.is_pinned ? "Unpin" : "Pin") + '</button><button class="btn" data-delete-notice="' + a.id + '">Delete</button></div></article>'
    ).join("");
    return intro("School announcements", "Publish notices to everyone, students or teachers. You can schedule and pin important updates.") +
      '<div class="card"><form id="announcementForm"><div class="fieldrow"><div><label for="noticeTitle">Title</label><input id="noticeTitle" required maxlength="120" placeholder="Unit test schedule updated"></div>' +
      '<div><label for="noticeAudience">Audience</label><select id="noticeAudience"><option value="all">Everyone</option><option value="student">Students only</option><option value="teacher">Teachers only</option></select></div></div>' +
      '<div class="fieldrow"><div><label for="noticeClass">Class restriction (optional)</label><input id="noticeClass" placeholder="Class 10"></div><div><label for="noticeStarts">Start time (optional)</label><input id="noticeStarts" type="datetime-local"></div></div>' +
      '<label for="noticeExpires">Expiry time (optional)</label><input id="noticeExpires" type="datetime-local">' +
      '<label for="noticeMessage">Message</label><textarea id="noticeMessage" required maxlength="3000" rows="4" placeholder="Write the announcement…"></textarea>' +
      '<label class="inline-check"><input id="noticePinned" type="checkbox"> Pin this announcement</label>' +
      '<div class="actions"><button class="btn primary" id="publishNotice">Publish announcement</button></div><div id="noticeError" class="error"></div></form></div>' +
      '<div class="section"><h3>Published notices · ' + adminAnnouncements.length + '</h3></div>' +
      (rows || tableEmpty("No announcements yet", "Create your first school-wide notice above."));
  }
  async function refreshNotices() {
    const { data, error } = await db.from("announcements").select("*").order("created_at", { ascending: false });
    if (error) throw error; adminAnnouncements = data || [];
  }
  async function createNotice(event) {
    event.preventDefault();
    const title = el("noticeTitle").value.trim(), message = el("noticeMessage").value.trim();
    const audience = el("noticeAudience").value, target = el("noticeClass").value.trim() || null;
    const starts = el("noticeStarts").value ? new Date(el("noticeStarts").value) : new Date();
    const expires = el("noticeExpires").value ? new Date(el("noticeExpires").value) : null;
    if (expires && expires <= starts) { el("noticeError").textContent = "Expiry must be later than the start time."; return; }
    const button = el("publishNotice"); button.disabled = true; el("noticeError").textContent = "";
    try {
      const { error } = await db.from("announcements").insert({
        title, message, audience, target_class: target, starts_at: starts.toISOString(),
        expires_at: expires ? expires.toISOString() : null, is_pinned: el("noticePinned").checked, created_by: user.id
      });
      if (error) throw error; await refreshNotices(); render();
    } catch (error) { el("noticeError").textContent = error.message || "Could not publish the announcement."; }
    finally { const b = el("publishNotice"); if (b) b.disabled = false; }
  }
  async function togglePin(id) {
    const row = adminAnnouncements.find(x => x.id === id); if (!row) return;
    const { error } = await db.from("announcements").update({ is_pinned: !row.is_pinned }).eq("id", id);
    if (error) { alert(error.message); return; } await refreshNotices(); render();
  }
  async function deleteNotice(id) {
    if (!confirm("Delete this announcement?")) return;
    const { error } = await db.from("announcements").delete().eq("id", id);
    if (error) { alert(error.message); return; } await refreshNotices(); render();
  }
  const originalRender = render;
  render = function () {
    originalRender();
    if (page === "announcements") {
      el("pageTitle").textContent = "Announcements"; el("page").innerHTML = renderAnnouncementManager();
      if (el("announcementForm")) el("announcementForm").onsubmit = createNotice;
      document.querySelectorAll("[data-pin-notice]").forEach(b => b.onclick = () => togglePin(b.dataset.pinNotice));
      document.querySelectorAll("[data-delete-notice]").forEach(b => b.onclick = () => deleteNotice(b.dataset.deleteNotice));
    }
    if (page === "overview") {
      const active = adminAnnouncements.filter(a => !a.expires_at || new Date(a.expires_at) > new Date()).length;
      const panel = document.createElement("div"); panel.className = "card feature-pulse";
      panel.innerHTML = '<div class="section"><h3>School communications</h3><span class="tag">ADMIN</span></div><p class="meta">' + active + ' active announcement(s). Use the Announcements section to publish notices, schedule updates and pin important messages.</p><button class="btn" id="quickAnnouncements">Manage announcements</button>';
      el("page").appendChild(panel); el("quickAnnouncements").onclick = () => { page = "announcements"; render(); };
    }
  };
  boot();
})();