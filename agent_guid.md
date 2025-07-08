Below is a **ready-to-commit** `docs/AGENT_GUIDE.md`.
Drop it into `docs/` and commit.

---

````markdown
# A Practical Guide to Building Agents  
*Blob Edge Stack – Operator Edition*

---

## Contents
1. [Introduction](#introduction)  
2. [What Is an Agent?](#what-is-an-agent)  
3. [When Should You Build an Agent?](#when-should-you-build-an-agent)  
4. [Agent Design Foundations](#agent-design-foundations)  
   1. [Selecting Models](#selecting-your-models)  
   2. [Defining Tools](#defining-tools)  
   3. [Configuring Instructions](#configuring-instructions)  
5. [Orchestration Patterns](#orchestration)  
   1. [Single-Agent Systems](#single-agent-systems)  
   2. [Multi-Agent Systems](#multi-agent-systems)  
6. [Guardrails](#guardrails)  
7. [Plan for Human Intervention](#plan-for-human-intervention)  
8. [Conclusion](#conclusion)  
9. [Appendix A – Blob Edge Agents Manifest](#appendix-a)

---

## Introduction
Large-language models (LLMs) can now reason, plan, and call external tools,
unlocking a new class of **LLM-powered agents**.  
This guide distills lessons from real deployments (including Blob Edge Stack) into
actionable patterns:

* How to **spot** high-leverage workflows for agents.  
* How to **design** agents—model + tools + instructions.  
* How to **orchestrate** single vs multi-agent systems.  
* How to **defend** with layered guardrails and human-in-the-loop.

Follow this playbook and you’ll ship reliable, self-healing agents instead of
one-off chatbots.

---

## What Is an Agent?
> **Definition** – *An agent is a system that autonomously executes a multi-step
> workflow on a user’s behalf.*

| Attribute                | Typical Automation | **Agent** |
|--------------------------|--------------------|-----------|
| Workflow ownership       | User triggers each step | Agent drives end-to-end |
| Decision-making          | Hard-coded rules   | LLM reasoning + context |
| Tool usage               | Pre-wired API calls| Dynamic tool selection |
| Failure handling         | Error out          | Retry, branch, or escalate |

### Examples vs Non-examples
*✅* Resolve a customer ticket **end-to-end** (agent).  
*❌* One-shot sentiment classifier (not an agent).

---

## When Should You Build an Agent?
Agents shine where deterministic logic hits diminishing returns:

| Criterion | Typical Signals |
|-----------|-----------------|
| **Complex judgement** | Fraud analysis, refund approval |
| **Rule-set sprawl** | 1000+ branching rules, hard to maintain |
| **Unstructured data** | PDF/legal review, conversational triage |

If your workflow is a straight SQL update—stick with code.  
If it requires nuance, context, or ever-changing rules—use an agent.

---

## Agent Design Foundations
Every agent = **Model + Tools + Instructions**

```python
weather_agent = Agent(
    name="Weather agent",
    instructions="You help users discuss the weather.",
    tools=[get_weather],
)
````

### Selecting Your Models

1. **Prototype** with the best model (accuracy first).
2. **Benchmark** – capture latency, cost, win-rate.
3. **Optimise** – replace steps with smaller models if quality holds.

### Defining Tools

Tools are typed functions—REST, on-chain calls, even other agents.

| Tool Type         | Purpose            | Examples                        |
| ----------------- | ------------------ | ------------------------------- |
| **Data**          | Fetch context      | SQL, PDF parser, web search     |
| **Action**        | Perform change     | sendEmail, swapExactETH         |
| **Orchestration** | Call another agent | refund\_agent(), write\_agent() |

### Configuring Instructions

Best practices:

* Lift wording from existing SOPs / runbooks.
* Number steps, state exit criteria.
* Enumerate edge-cases (“If order ID missing, ask once, then escalate.”).

Prompt template to convert docs →

```
You are an expert instruction writer.
Turn the following SOP into numbered, unambiguous steps: {{doc}}
```

---

## Orchestration

### Single-Agent Systems

Start here. One loop, exit when:

* Tool call succeeds
* Structured JSON returned
* Error or max-turn reached

### Multi-Agent Systems

Split only when prompts become spaghetti.

* **Manager pattern** – central router → specialised agents.
* **Decentralised** – peers hand off tasks (e.g., triage → tech support).

Example Manager →

```python
manager = Agent(
  name="translate_mgr",
  tools=[
    es_agent.as_tool("to_es"),
    fr_agent.as_tool("to_fr")
  ],
)
```

---

## Guardrails

Layer defence:

1. **LLM classifiers** – relevance, safety, PII.
2. **Rules** – regex, length caps, allowlists.
3. **Moderation APIs** – OpenAI moderation.
4. **Tool-level** – risk-score, human review for large refunds.
5. **Output validation** – brand tone, no secrets.

### Guardrail Tripwire Example (Python)

```python
@input_guardrail
async def churn_tripwire(ctx, agent, input):
    out = await Runner.run(churn_detector, input, ctx=ctx)
    return GuardrailFunctionOutput(out, out.is_churn_risk)
```

If `is_churn_risk` → raise `GuardrailTripwireTriggered`.

---

## Plan for Human Intervention

* Escalate when guardrails trip repeatedly.
* Require approval for high-risk tools (e.g., `safeExec()` on-chain).
* Store transcripts for post-mortems.

---

## Conclusion

* Start single-agent, add tools.
* Split to multi-agent only when complexity demands.
* Layer guardrails and human checkpoints.
* Iterate with live telemetry.

Done right, agents unlock full‐cycle automation and compounding operating leverage.

---

## Appendix A – Blob Edge Agents Manifest

The live manifest is in `config/agents.json`.
It lists every specialised agent—CI, deploy, feeders, daemons—along with
guardrails and KPI hooks.
Update that file to add new bots; `scripts/launch_agents.ts`  bootstraps
them automatically.

```
```
