# AgentOps Command Center

> A full-stack AI agent operations platform for managing, monitoring, and orchestrating intelligent agents across business departments.

![Dashboard Preview](./docs/dashboard_1.png)
🔗 **Live Demo**: [agentops.vercel.app](https://agentops.vercel.app) &nbsp;|&nbsp; ⭐ Star this repo if it helped you

---

## What Is This?

AgentOps is a production-ready AI operations dashboard I built to explore how businesses can practically deploy and manage multiple AI agents across departments. It's not a toy — the agents are real, the data persists, and the routing logic is functional.

The core idea: most AI demos show a single chatbot. Real business operations need **many** specialized agents, coordinated routing, shared knowledge, audit trails, and management visibility. This is what that looks like.

---

## Features

### 🤖 Multi-Agent Ecosystem
- 5 specialized department agents (Sales, Support, Compliance, HR, Operations)
- Each agent has a unique system prompt, capabilities list, and performance metrics
- Live AI chat powered by **Google Gemini** with function calling
- Agents can call tools: search the knowledge base, log actions, or hand off to a specialist

### 🔄 Visual Workflow Pipelines
- n8n-style visual pipeline canvas with animated node connections
- Three pre-built pipelines: Lead Qualification, Support Routing, Compliance Monitoring
- Live "Simulate" mode — watch data flow through decision branches in real time
- Toggle workflows active/inactive, view run history and stats

### 🔀 Inter-Agent Handoff & Routing
- Submit any business query and watch the routing AI classify and dispatch it
- Animated network map shows which agent receives the task and why
- Routing decisions are logged with full reasoning from Gemini
- Agents can trigger handoffs mid-conversation via function calls

### 📚 Knowledge Base with Version Control
- Full CRUD for internal documents (Policies, Procedures, Regulatory, Training)
- Every edit creates a versioned snapshot — nothing is ever overwritten
- Line-by-line diff viewer to compare any two versions
- Articles are accessible to agents via the `search_knowledge_base` function tool

### 📊 Performance Dashboard
- Live KPI cards: active agents, tasks completed, success rate, avg response time
- Department performance breakdown with animated chart (Recharts AreaChart)
- Real-time activity feed pulling from the central log store

### 📋 Centralized Logging Infrastructure
- Every agent action is captured with severity, timestamp, and department
- Filter logs by severity, department, and time range
- Export filtered logs to **CSV** or **JSON** with one click
- Real-time polling mode (refreshes every 5 seconds)

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Frontend | React + Vite | Fast dev server, clean component model |
| Styling | Vanilla CSS (dark theme) | Full design control, no framework lock-in |
| Charts | Recharts | Lightweight, composable, React-native |
| Icons | Lucide React | Consistent, tree-shakeable |
| Routing | React Router v6 | Standard SPA routing |
| Backend | Express.js | Minimal REST API, easy to extend |
| Database | Supabase (PostgreSQL) | Managed Postgres with real-time and RLS |
| AI | Google Gemini API | Function calling, multi-turn chat |
| Deployment | Vercel (FE) + Render (BE) | Free tier, auto-deploys from GitHub |

---

## Architecture

![Architecture](./docs/Architecture_Diagram.png)

### How Gemini Function Calling Works Here

Instead of using an agent SDK, I implemented function calling directly against the Gemini API. Each agent is initialized with:
1. A **system prompt** defining its role and personality
2. A set of **function declarations** (tools it can use)

When a user messages an agent, Gemini decides whether to respond directly or call a tool. The backend handles the tool execution and feeds results back to Gemini for a final response. This loop can chain — e.g., an agent searches the KB, gets results, then responds and logs the action, all in one turn.

![Architecture](./docs/Architecture_Diagram_2.png)

---

## Database Schema

```sql
agents          -- Agent profiles, system prompts, performance metrics
agent_logs      -- Centralized audit log for all agent actions
kb_articles     -- Knowledge base documents (current version)
kb_versions     -- Full version history for every article (append-only)
workflows       -- Visual pipeline definitions (steps stored as JSONB)
chat_messages   -- Persisted conversation history per agent
```

---

## Getting Started

### Prerequisites
- Node.js 18+
- A [Supabase](https://supabase.com) account (free)
- A [Google AI Studio](https://aistudio.google.com) API key (free)

### 1. Clone and Install

```bash
git clone https://github.com/yourusername/agentops-command-center.git
cd agentops-command-center

# Install backend dependencies
cd server && npm install

# Install frontend dependencies
cd ../client && npm install
```

### 2. Set Up Supabase

1. Create a new Supabase project
2. Open the SQL Editor and run the full schema from [`/database/schema.sql`](./database/schema.sql)
3. This creates all 6 tables and seeds the initial agents, KB articles, workflows, and logs

### 3. Configure Environment

Create `server/.env`:

```env
GEMINI_API_KEY=your_gemini_api_key_here
SUPABASE_URL=https://yourproject.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key_here
PORT=3001
CORS_ORIGIN=http://localhost:5173
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=120
```

Use `server/.env.example` as the template for local setup and deployment environments.

### 4. Run Locally

```bash
# Terminal 1 — Backend
cd server && npm run dev
# Runs on http://localhost:3001

# Terminal 2 — Frontend
cd client && npm run dev
# Runs on http://localhost:5173
```

---

## Deployment

### Frontend → Vercel
```bash
cd client
npm run build
# Deploy the dist/ folder to Vercel
# Or connect your GitHub repo for auto-deploys
```

### Backend → Render
1. Create a new Web Service on [render.com](https://render.com)
2. Point it to the `/server` directory
3. Set start command: `node index.js`
4. Add your env vars in the Render dashboard
5. Update `client/src/utils/api.js` `BASE_URL` to your Render URL

Security note:
- Never commit real secret values.
- Restrict `CORS_ORIGIN` to your deployed frontend origin(s).
- Rotate any key that has ever been exposed.

---

## Project Structure

```
agentops-command-center/
├── client/                    # React frontend
│   └── src/
│       ├── pages/             # Route-level pages
│       ├── components/        # Reusable UI components
│       ├── styles/            # Global CSS design system
│       └── utils/api.js       # API helper layer
├── server/                    # Express backend
│   ├── routes/                # REST route handlers
│   ├── gemini.js              # Gemini client + function calling
│   └── supabase.js            # Supabase client
├── database/
│   └── schema.sql             # Full DB schema + seed data
└── README.md
```

---

## What I Learned

- **Function calling is more powerful than system-prompt engineering alone** — giving agents tools lets them ground responses in real data instead of hallucinating
- **Routing intelligence is non-trivial** — even with a good classifier, edge cases (mixed queries, ambiguous intent) need fallback logic
- **Version control for knowledge bases matters** — without it, you have no audit trail when regulated content changes
- **Supabase RLS policies** are essential for production but need careful design when multiple agents share tables

---

## Roadmap

- [ ] WebSocket support for true real-time log streaming
- [ ] Agent-to-agent messaging (async task queue)
- [ ] Workflow trigger webhooks (connect to external tools)
- [ ] Role-based access control (admin vs viewer)
- [ ] Agent performance alerts and anomaly detection

---

## License

MIT — use it, fork it, build on it.

---

*Built by M. Basera [baseramarlvin@gmail.com](baseramarlvin@gmail.com)— open to collaboration and feedback.* 