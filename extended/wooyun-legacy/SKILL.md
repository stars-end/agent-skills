---
name: wooyun-legacy
description: WooYun漏洞分析专家系统。提供基于88,636个真实漏洞案例提炼的元思考方法论、测试流程和绕过技巧。适用于漏洞挖掘、渗透测试、安全审计及代码审计。支持SQL注入、XSS、命令执行、逻辑漏洞、文件上传、未授权访问等多种漏洞类型。
---

# WooYun漏洞分析专家系统 (WooYun Legacy)

WooYun Legacy is a specialized skill for vulnerability analysis and penetration testing, based on the collective wisdom of the WooYun platform (2010-2016). It provides a deep knowledge base of real-world vulnerabilities and bypass techniques.

## Core Methodology: The Meta-Thinking Framework

To identify vulnerabilities effectively, use the following question chain:
1. **Data Source**: Where does the data come from? (GET, POST, Cookie, Header, File)
2. **Data Flow**: Trace the data from input → validation → processing → storage → output.
3. **Trust Boundary**: Identify where the application transitions from untrusted to trusted environments.
4. **Processing Logic**: Analyze how data is handled (filtering, escaping, validation, execution).
5. **Output Sink**: Where does the processed data end up? (HTML, SQL, OS Command, File System)

## Vulnerability Type Index & References

For detailed methodology and bypass techniques, refer to the following files in `references/`:

| Vulnerability Type | Reference File | Case Database |
| :--- | :--- | :--- |
| **SQL Injection** | [sql-injection.md](references/sql-injection.md) | [cases-sql-injection.md](references/cases-sql-injection.md) |
| **XSS (Cross-Site Scripting)** | [xss.md](references/xss.md) | [cases-xss.md](references/cases-xss.md) |
| **Command Execution** | [command-execution.md](references/command-execution.md) | [cases-command-execution.md](references/cases-command-execution.md) |
| **Logic Flaws** | [logic-flaws.md](references/logic-flaws.md) | [cases-logic-flaws.md](references/cases-logic-flaws.md) |
| **File Upload** | [file-upload.md](references/file-upload.md) | [cases-file-upload.md](references/cases-file-upload.md) |
| **Unauthorized Access** | [unauthorized-access.md](references/unauthorized-access.md) | [cases-unauthorized-access.md](references/cases-unauthorized-access.md) |
| **Information Disclosure** | [info-disclosure.md](references/info-disclosure.md) | [cases-info-disclosure.md](references/cases-info-disclosure.md) |
| **File Traversal** | [file-traversal.md](references/file-traversal.md) | [cases-file-traversal.md](references/cases-file-traversal.md) |
| **SSRF / CSRF / XXE** | See categories | `cases-ssrf.md`, `cases-csrf.md`, `cases-xxe.md` |

## How to Conduct a Security Review

### 1. Information Gathering & Attack Surface Mapping
- Map all inputs (parameters, headers, file uploads).
- Identify interesting endpoints (admin panels, password resets, payment gateways).
- Analyze client-side JS for API endpoints and hidden logic.

### 2. Manual Review (WooYun Style)
- **Think like an attacker**: Challenge every assumption made by the developer.
- **Search for patterns**: Use `grep` to find dangerous functions (e.g., `eval`, `system`, `mysql_query`).
- **Consult the knowledge base**: If you find a potential injection point, check the corresponding reference file in `references/` for bypass payloads.

### 3. Verification & Proof of Concept (PoC)
- Draft a PoC to demonstrate the vulnerability without causing harm.
- For blind injections or RCE, use time-based delays or OOB (out-of-band) techniques.

## Searching the Case Database
The case database (`cases-*.md` files) contains thousands of real-world examples. Use `grep` or `search_file_content` to find relevant cases:
- `grep -i "bypass filter" references/cases-xss.md`
- `grep -i "reset password" references/cases-logic-flaws.md`

## Integration with Security SOP
This skill supports the **Manual Review** option of the standard security analysis procedure. Use the WooYun methodology to provide high-fidelity findings with clear impact and remediation.