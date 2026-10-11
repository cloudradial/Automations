# Course Management

> Build training courses from a topic, document, or YouTube link, all from a chat prompt.

**Say this:**

```
Build a phishing-awareness training course for Contoso with 5 lessons and a final exam lesson
```

<img src="images/skill-result.png" alt="Training course in CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Build a training course
`Per-company` · `Writes to the portal` · **Partly works**

```
Build a phishing-awareness course for Contoso with five short lessons and a
final exam lesson. Show me the outline first and only create it when I
confirm. Don't put a pass score in the lesson text.
```

**What you get:** The course and its lessons, created after you approve the outline.

**Good to know:** The exam passing score can't be set through the API (UCP-1969). Set it in the portal after the course is built.

### Build a course from a document
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Build a course for Contoso from the attached document. Split it into lessons
by heading, show me the outline, and only create it when I confirm.
```

**What you get:** Lessons built from your document.

### Build a course from a video
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Build a course for Contoso from this YouTube video: <link>. Summarize it into
lessons, show me the outline, and only create it when I confirm.
```

**What you get:** Lessons built from the video.

### Check who finished
`Per-company` · `Read-only` · **Tested**

```
Who has completed the security training at Acme Corp? Show name, completion
date, and who is still in progress.
```

**What you get:** Enrollments with completion dates.

**Good to know:** Enrollments can't be deleted through the API, and a completion score isn't stored on them.

### Find where someone stopped
`Per-company` · `Read-only` · **Tested**

```
Which lesson did Sam stop at in the phishing course at Contoso?
```

**What you get:** Lesson-by-lesson progress for one person.

## Good to know

- **Course creation is two-step:** the course is created first, then each lesson.
- **Set the exam passing score in the portal.** The API can't save it (UCP-1969).
- **YouTube/doc/image sources**: Claude reads and summarizes the content; the plugin stores the resulting course.
- **Course uses `name`, lesson uses `title`**: different field names for the container vs. its children.

## Related skills

- [Content Management](../content-management): for KB articles and service catalogs.
- [User Management](../user-management): to check who's enrolled and who's completed.
