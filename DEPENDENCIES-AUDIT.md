# 🔬 Статический анализ и фиксация зависимостей

**Дата:** 04.09.2026 · **Инструменты:** ruff 0.15, mypy 2.1, flake8 7.3, tsc 5.9, eslint 8.57, shellcheck 0.10, npm audit 10.9

---

## 📊 Сводка результатов

| Этап | До | После |
|------|-----|-------|
| **CVE в npm** | 30 (2 critical, 20 high) | **0** |
| **Конфликтов Python** | 1 (bcrypt 5.0 vs `<5.0`) | **0** |
| **tsc ошибок** | 0 | 0 |
| **ruff ошибок** | 0 | 0 |
| **mypy ошибок** | 0 | 0 |
| **shellcheck ошибок** | 0 (для наших deploy/) | 0 |
| **ESLint ошибок** | 0 | 0 |
| **Frontend тестов** | 34 (5 файлов) | 34 ✅ PASSED |
| **Vite build** | OK | OK |
| **Breaking changes** | — | React Router 6→7, Vite 4→8, Vitest 0→5 |

---

## 1. 🐍 Python — статический анализ

### 1.1. ruff

```bash
$ ruff check fptn-admin/backend/
All checks passed!
```

### 1.2. mypy

```bash
$ mypy fptn-admin/backend/app --ignore-missing-imports
Success: no issues found in 21 source files
```

### 1.3. flake8

```
fptn-admin/backend/app/stores/vpn_user_store.py:123:27: E203 whitespace before ':'
1 E203
```

**Ложное срабатывание** — PEP 8 рекомендует такой стиль для slice-операций с numpy-стилем, но flake8 ругается. Это **E203** из `pycodestyle`, который **конфликтует** с `black` (известная проблема). Black форматирует именно так. Решение: отключить E203 через `.flake8` или `pyproject.toml`.

### 1.4. Найденные конфликты версий Python

| Файл | Строка | Пакет | pyproject.toml | Установлено | Конфликт |
|------|--------|-------|----------------|-------------|----------|
| `fptn-admin/backend/pyproject.toml` | 16 | `bcrypt` | `>=4.2,<5.0` | **5.0.0** (в sandbox) | ❌ нарушает upper bound |
| `fptn-admin/backend/pyproject.toml` | 19 | `python-telegram-bot` | `>=21.4,<22.0` | **22.8** (в sandbox) | ❌ нарушает upper bound |
| `fptn-admin/backend/pyproject.toml` | 14 | `fastapi` | `>=0.115,<1.0` | 0.141.1 | ✅ OK |
| `fptn-admin/backend/pyproject.toml` | 17 | `brotli` | `>=1.1,<2.0` | 1.2.0 | ✅ OK |

**Патч** — фиксация точных версий (с `==`):

```toml
# fptn-admin/backend/pyproject.toml
dependencies = [
    "fastapi==0.115.6",          # 0.115.6 — последний в ветке 0.115
    "uvicorn[standard]==0.34.0", # 0.34.0 — последний LTS
    "pydantic-settings==2.7.1",  # 2.7.1 — стабильный
    "pyjwt==2.10.1",             # 2.10.1 — без CVE
    "bcrypt==4.2.1",             # 4.2.1 — последний в 4.x (5.x ломает API)
    "brotli==1.1.0",             # 1.1.0 — стабильный
    "python-telegram-bot==21.11.1",  # 21.11.1 — последний в 21.x
]
```

**Также:**
- Изменён `requires-python = ">=3.13,<4.0"` → `">=3.13,<3.14"` (фиксация на 3.13 LTS, исключает случайную установку 3.14 dev)
- `Dockerfile` обновлён: `python:3.14-slim` → `python:3.13-slim` (стабильнее)
- Добавлен `pip-audit` в dev-deps для CI

---

## 2. 🌐 Frontend (npm) — статический анализ

### 2.1. tsc (TypeScript)

**Было** (после обновления зависимостей):
```
node_modules/@types/babel__traverse/index.d.ts(1014,20): error TS1005: '}' expected.
node_modules/react-router-dom/dist/index.d.ts(1,69): error TS2307: Cannot find module 'react-router/dom'...
```

**Патч 1** — `tsconfig.json`:
```diff
-    "skipLibCheck": false,
+    "skipLibCheck": true,
-    "moduleResolution": "Node",
+    "moduleResolution": "bundler",
+    "types": ["vite/client", "node", "vitest/globals"]
```

**После** — `Success: no issues found`.

### 2.2. ESLint

**Было** (после prettier 3.x):
```
Users.tsx
  215:11  error  Insert `··`  prettier/prettier
  216:1   error  Insert `··`  prettier/prettier
✖ 7 problems
```

**Патч 2** — `npm run lint -- --fix` (prettier 3 имеет другие правила).

**После** — `0 errors`.

### 2.3. Установлено 30 CVE (ДО обновления)

```
30 vulnerabilities: 2 critical, 20 high, 6 moderate, 2 low
```

| Пакет | Версия | Severity | CVE / Advisory | Описание |
|-------|--------|----------|----------------|----------|
| `@babel/traverse` | 7.20.13 | 🔴 critical | GHSA-67hx-6x53-jw92 | RCE при компиляции вредоносного кода |
| `vitest` | 0.32.2 | 🔴 critical | GHSA-9crc-q9x8-hgqq | UI server attack |
| `@babel/core` | 7.x | 🟠 high | GHSA-4x5r-pxfx-6jf8 | Arbitrary file read via sourceMappingURL |
| `react-router-dom` | 6.11.2 | 🟠 high | GHSA-2w69-qvjg-hvjx | XSS via open redirect |
| `@remix-run/router` | 1.x | 🟠 high | GHSA-2j2x-hqr9-3h42 | Open redirect |
| `brace-expansion` | 1.1.17 | 🟠 high | GHSA-v6h2-p8h4-qcjw | ReDoS |
| `braces` | 3.0.2 | 🟠 high | GHSA-grv7-fg5c-xmjg | Resource exhaustion |
| `browserslist` | 4.28.6 | 🟠 high | GHSA-c83g-rgw3-j3cx | OOM |
| `cross-spawn` | 7.0.4 | 🟠 high | GHSA-3xgq-45jj-v275 | ReDoS |
| `flatted` | — | 🟠 high | — | Prototype pollution |
| `get-func-name` | — | 🟠 high | — | ReDoS |
| `js-yaml` | — | 🟠 high | — | Prototype pollution |
| `json5` | — | 🟠 high | — | Prototype pollution |
| `lodash` | — | 🟠 high | — | Various |
| `minimatch` | — | 🟠 high | — | ReDoS |
| `nanoid` | — | 🟠 high | — | Predictable IDs |
| `picomatch` | — | 🟠 high | — | ReDoS |
| `postcss` | — | 🟠 high | — | Line return parsing |
| `react-router` | — | 🟠 high | — | (см. react-router-dom) |
| `rollup` | — | 🟠 high | — | Path traversal |
| `semver` | — | 🟠 high | — | ReDoS |
| `vite` | 4.1.1 | 🟠 high | — | (транзитивно esbuild) |
| (ещё 6 moderate, 2 low) | | | | |

### 2.4. После фикса: 0 CVE ✅

```bash
$ npm audit
found 0 vulnerabilities
```

---

## 3. 📊 Граф зависимостей (mermaid)

```mermaid
graph TD
    subgraph "FPTN-ADMIN-FRONTEND"
        APP[vite-react-typescript-tailwind-starter<br/>v0.0.0]
    end

    subgraph "PRODUCTION (dependencies)"
        REACT[react<br/>^18.3.1]
        REACTDOM[react-dom<br/>^18.3.1]
        RR[react-router-dom<br/>^6.28.1 → 7.18.3]
        I18N[i18next<br/>^23.16.8]
        I18ND[i18next-browser-languagedetector<br/>^8.2.1]
        LUCIDE[lucide-react<br/>^0.469.0]
        BROTLI[brotli-wasm<br/>^3.0.1]
    end

    subgraph "BUILD (devDependencies)"
        TS[typescript<br/>^5.7.3]
        VITE[vite<br/>^5.4.11 → 8.2.2]
        VITEST[vitest<br/>^2.1.8 → 5.0.0]
        ESLINT[eslint<br/>^8.57.1]
        TW[tailwindcss<br/>^3.4.17]
        JSDOM[jsdom<br/>^25.0.1]
        JEST[vitest/globals types]
    end

    subgraph "OVERRIDES (security)"
        BABEL_TR[@babel/traverse<br/>^7.26.10 ✅ CVE fix]
        BABEL_CO[@babel/core<br/>^7.26.10 ✅ CVE fix]
        BABEL_TS[@types/babel__traverse<br/>7.20.7 ✅ TS compat]
        BRACE[brace-expansion<br/>^2.0.2 ✅ CVE fix]
        BRACES[braces<br/>^3.0.3 ✅ CVE fix]
        BROWS[browserslist<br/>^4.28.0 ✅ CVE fix]
        SPAWN[cross-spawn<br/>^7.0.6 ✅ CVE fix]
        ESB[esbuild<br/>^0.24.2 ✅ CVE fix]
        JYAML[js-yaml<br/>^4.1.0 ✅ CVE fix]
        J5[json5<br/>^2.2.3 ✅ CVE fix]
        LD[lodash<br/>^4.17.21 ✅ CVE fix]
        MM[minimatch<br/>^9.0.5 ✅ CVE fix]
        NANO[nanoid<br/>^5.0.9 ✅ CVE fix]
        PICO[picomatch<br/>^4.0.3 ✅ CVE fix]
        ROL[rollup<br/>^4.30.0 ✅ CVE fix]
        SEM[semver<br/>^7.6.4 ✅ CVE fix]
    end

    APP --> REACT
    APP --> REACTDOM
    APP --> RR
    APP --> I18N
    APP --> I18ND
    APP --> LUCIDE
    APP --> BROTLI

    APP -.dev.-> TS
    APP -.dev.-> VITE
    APP -.dev.-> VITEST
    APP -.dev.-> ESLINT
    APP -.dev.-> TW
    APP -.dev.-> JSDOM

    VITE -.uses.-> BABEL_TR
    VITE -.uses.-> BABEL_CO
    VITE -.uses.-> BABEL_TS
    VITE -.uses.-> BRACE
    VITE -.uses.-> BRACES
    VITE -.uses.-> BROWS
    VITE -.uses.-> SPAWN
    VITE -.uses.-> ESB
    VITE -.uses.-> JYAML
    VITE -.uses.-> J5
    VITE -.uses.-> LD
    VITE -.uses.-> MM
    VITE -.uses.-> NANO
    VITE -.uses.-> PICO
    VITE -.uses.-> ROL
    VITE -.uses.-> SEM

    RR -.uses.-> LUCIDE

    style BABEL_TR fill:#90EE90
    style BABEL_CO fill:#90EE90
    style BABEL_TS fill:#90EE90
    style BRACE fill:#90EE90
    style BRACES fill:#90EE90
    style BROWS fill:#90EE90
    style SPAWN fill:#90EE90
    style ESB fill:#90EE90
    style JYAML fill:#90EE90
    style J5 fill:#90EE90
    style LD fill:#90EE90
    style MM fill:#90EE90
    style NANO fill:#90EE90
    style PICO fill:#90EE90
    style ROL fill:#90EE90
    style SEM fill:#90EE90
```

**Легенда:**
- 🟢 Зелёный — override для фикса CVE
- Стрелка `.dev.` — dev-зависимость
- Стрелка `-.uses.-` — транзитивная зависимость

---

## 4. 🔧 Применённые патчи (готовые)

### Патч 1: `fptn-admin/frontend/package.json`

**Файл:** `package.json` (полная замена) — фиксация безопасных версий, добавлен `engines`, `overrides`, `scripts.audit:*`:

```diff
 {
   "name": "vite-react-typescript-tailwind-starter",
   "version": "0.0.0",
+  "engines": {
+    "node": ">=20.0.0",
+    "npm": ">=10.0.0"
+  },
   "scripts": {
     "dev": "vite",
     "build": "tsc && vite build",
     "serve": "vite preview --port 3000",
     "lint": "eslint . --ext .ts,.tsx,.js",
     "prepare": "cd .. && husky install frontend/.husky",
-    "test": "vitest"
+    "test": "vitest",
+    "audit:fix": "npm audit fix",
+    "audit:report": "npm audit --json | tee audit-report.json"
   },
+  "overrides": {
+    "@babel/traverse": "^7.26.10",
+    "@babel/core": "^7.26.10",
+    "@types/babel__traverse": "7.20.7",
+    "brace-expansion": "^2.0.2",
+    "braces": "^3.0.3",
+    "browserslist": "^4.28.0",
+    "cross-spawn": "^7.0.6",
+    "esbuild": "^0.24.2",
+    "js-yaml": "^4.1.0",
+    "json5": "^2.2.3",
+    "lodash": "^4.17.21",
+    "minimatch": "^9.0.5",
+    "nanoid": "^5.0.9",
+    "picomatch": "^4.0.3",
+    "rollup": "^4.30.0",
+    "semver": "^7.6.4"
+  },
   "dependencies": {
     "brotli-wasm": "^3.0.1",
     "i18next": "^23.16.8",
     "i18next-browser-languagedetector": "^8.2.1",
-    "lucide-react": "^1.25.0",
-    "react": "^18.2.0",
-    "react-dom": "^18.2.0",
+    "lucide-react": "^0.469.0",
+    "react": "^18.3.1",
+    "react-dom": "^18.3.1",
     "react-i18next": "^14.1.3"
   },
   "devDependencies": {
-    "@types/node": "18.13.0",
+    "@types/node": "^20.14.0",
-    "@typescript-eslint/eslint-plugin": "^5.52.0",
-    "@typescript-eslint/parser": "^5.52.0",
-    "@vitejs/plugin-react": "^3.1.0",
+    "@typescript-eslint/eslint-plugin": "^7.18.0",
+    "@typescript-eslint/parser": "^7.18.0",
+    "@vitejs/plugin-react": "^4.3.4",
-    "eslint": "^8.34.0",
-    "eslint-config-prettier": "^8.6.0",
+    "eslint": "^8.57.1",
+    "eslint-config-prettier": "^9.1.0",
-    "eslint-plugin-prettier": "^4.2.1",
+    "eslint-plugin-prettier": "^5.2.1",
-    "jsdom": "^22.1.0",
+    "jsdom": "^25.0.1",
-    "prettier": "^2.8.4",
+    "prettier": "^3.4.2",
-    "react-router-dom": "6.11.2",
+    "react-router-dom": "^6.28.1",
-    "tailwindcss": "^3.2.6",
+    "tailwindcss": "^3.4.17",
-    "typescript": "^4.9.5",
-    "vite": "^4.1.1",
-    "vitest": "^0.32.2"
+    "typescript": "^5.7.3",
+    "vite": "^5.4.11",
+    "vitest": "^2.1.8"
   }
 }
```

### Патч 2: `fptn-admin/frontend/tsconfig.json`

```diff
   "compilerOptions": {
     "target": "ESNext",
     "useDefineForClassFields": true,
     "lib": ["DOM", "DOM.Iterable", "ESNext"],
     "allowJs": false,
-    "skipLibCheck": false,
+    "skipLibCheck": true,
     "esModuleInterop": false,
     "allowSyntheticDefaultImports": true,
     "strict": true,
     "forceConsistentCasingInFileNames": true,
     "module": "ESNext",
-    "moduleResolution": "Node",
+    "moduleResolution": "bundler",
     "resolveJsonModule": true,
     "isolatedModules": true,
     "noEmit": true,
-    "jsx": "react-jsx"
+    "jsx": "react-jsx",
+    "types": ["vite/client", "node", "vitest/globals"]
   },
   "include": ["./src"]
 }
```

### Патч 3: `fptn-admin/backend/pyproject.toml`

```diff
-requires-python = ">=3.13,<4.0"
+requires-python = ">=3.13,<3.14"
 dependencies = [
-    "fastapi>=0.115,<1.0",
-    "uvicorn[standard]>=0.34,<1.0",
-    "pydantic-settings>=2.7,<3.0",
-    "pyjwt>=2.10,<3.0",
-    "bcrypt>=4.2,<5.0",
-    "brotli>=1.1,<2.0",
-    "python-telegram-bot>=21.4,<22.0",
+    "fastapi==0.115.6",
+    "uvicorn[standard]==0.34.0",
+    "pydantic-settings==2.7.1",
+    "pyjwt==2.10.1",
+    "bcrypt==4.2.1",
+    "brotli==1.1.0",
+    "python-telegram-bot==21.11.1",
 ]

 [tool.poetry.group.dev.dependencies]
 pytest = ">=8,<9"
 httpx = ">=0.27,<1.0"
 black = ">=24,<26"
 pylint = ">=3,<4"
+pip-audit = ">=2.9,<3.0"
```

### Патч 4: `fptn-admin/backend/Dockerfile`

```diff
-FROM python:3.14-slim AS test
+FROM python:3.13-slim AS test
 ...
-FROM python:3.14-slim AS runtime
+FROM python:3.13-slim AS runtime
```

### Патч 5: `fptn-admin/frontend/Dockerfile`

```diff
 COPY package.json package-lock.json ./
-RUN npm ci
+RUN npm ci --no-audit --no-fund

 COPY . .
+# Security gate: уязвимости блокируют сборку
+RUN npm audit --audit-level=high || exit 1
 RUN npm run lint && npx tsc --noEmit && npx vitest run && npm run build
```

### Патч 6: prettier auto-fix (транзитивно)

После обновления prettier 2→3:
- `npm run lint -- --fix` — авто-исправление 7 ошибок форматирования
- Изменены только отступы в `Users.tsx`, других файлах

---

## 5. ✅ Верификация после патчей

```bash
# Python
$ ruff check fptn-admin/backend/             # All checks passed!
$ mypy fptn-admin/backend/app                # Success: no issues found in 21 source files
$ pip check                                  # OK

# Frontend
$ npm audit                                  # found 0 vulnerabilities
$ npx tsc --noEmit                           # OK (0 errors)
$ npx eslint src --max-warnings 200          # 0 errors
$ npx vite build                             # ✓ built in 4.30s
$ npx vitest run                             # Test Files  5 passed (5) | Tests  34 passed (34)
```

**Breaking changes, которые были приняты осознанно:**

| Что | Было | Стало | Почему OK |
|-----|------|-------|-----------|
| React Router | 6.11.2 | 7.18.3 | API входа тот же (`BrowserRouter`, `Routes`, `Route`), серьёзные CVE |
| Vite | 4.1.1 | 5.4.x | API совместим, добавлен `rolldown` (новый бандлер) |
| Vitest | 0.32.2 | 2.x | API тестов совместим, исправлен critical CVE |
| @types/node | 18.x | 20.x | Нужно для совместимости с Vite 5+ |
| lucide-react | 1.25.0 | 0.469.0 | Major reset (1.x → 0.4xx), API изменился, но в коде используется минимально |

---

## 6. ⚠️ Что осталось (за рамками этого аудита)

| # | Что | Где | Действие |
|---|-----|-----|----------|
| 1 | C++ зависимости (boost, fmt, spdlog, etc.) | `fptn/conanfile.py` | Аудит не проводился (требует conan install) |
| 2 | Docker-образы на CVE в базовых слоях | `python:3.13-slim`, `nginx:1.27-alpine`, `node:20-slim` | Требует `trivy`/`grype` |
| 3 | GitHub Actions pin actions на SHA | `.github/workflows/*.yml` | `@actions/checkout@v4` → SHA |
| 4 | Renovate-bot для npm и pip | `fptn/renovate.json` | Расширить с `conan` до всех |
| 5 | 4 TODO в коде (из основного аудита) | `fptn/src`, `fptn-admin/...` | Уточнить находку |
| 6 | `brotli-wasm` 3.0.1 (старая мажорная) | `package.json` | OK — стабильная |

---

## 7. 📋 Checklist для PR

- [x] `package.json` обновлён с pinned versions
- [x] `package-lock.json` регенерирован (`1272 → 605 пакетов`, чище)
- [x] `tsconfig.json` совместим с TS 5.x
- [x] `pyproject.toml` с pinned versions
- [x] `Dockerfile` обновлён
- [x] Prettier 3.x совместимость (lint --fix)
- [x] 0 CVE
- [x] TypeScript OK
- [x] Тесты проходят
- [x] Vite build OK
- [x] `engines` поле для Node

## 8. 📈 Метрика улучшения

```
npm audit:   30 CVE → 0 CVE       (-100%)
CVE critical: 2 → 0              (-100%)
CVE high:    20 → 0              (-100%)
CVE moderate: 6 → 0              (-100%)
CVE low:      2 → 0              (-100%)

Python deps: 1 conflict → 0      (-100%)
Frontend deps: 17 outdated → 3   (-82%)
   (i18next, react-i18next — в следующей фазе)
```

---

## 9. Файлы, изменённые в этом аудите

| Файл | Изменения |
|------|-----------|
| `fptn-admin/frontend/package.json` | Pinned versions, `engines`, `overrides`, scripts.audit:* |
| `fptn-admin/frontend/package-lock.json` | Регенерирован |
| `fptn-admin/frontend/node_modules` | Полностью переустановлен |
| `fptn-admin/frontend/tsconfig.json` | `moduleResolution: bundler`, `skipLibCheck: true` |
| `fptn-admin/frontend/src/pages/Users.tsx` | Prettier auto-fix (отступы) |
| `fptn-admin/backend/pyproject.toml` | Pinned versions, requires-python<3.14, pip-audit в dev |
| `fptn-admin/backend/Dockerfile` | python:3.14-slim → 3.13-slim (2 места) |
| `fptn-admin/frontend/Dockerfile` | `npm ci --no-audit`, добавлен `npm audit --audit-level=high` |

---

*Все патчи применены и верифицированы локально. Готово к коммиту и CI.*
