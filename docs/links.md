# 🔗 Справочник ссылок FPTN

> Все ссылки, которые могут понадобиться при работе с FPTN. Структурированы по категориям.

---

## 📦 Upstream-репозитории

| Ресурс | URL | Назначение |
|--------|-----|-----------|
| **Оригинальный FPTN** | <https://github.com/batchar2/fptn> | C++20 ядро, оригинальная разработка |
| **fptn-admin (upstream)** | <https://github.com/fptn-project/fptn-admin> | Веб-панель администратора |
| **Наш форк (этот репо)** | <https://github.com/ZDarow/FTPN> | Этот репозиторий — ZDarow/FTPN с deploy-инфраструктурой |

---

## 🖥️ Клиенты и сайт проекта

| Ресурс | URL | Назначение |
|--------|-----|-----------|
| **Сайт / клиенты** | <https://storage.googleapis.com/fptn.org/> | Официальные клиенты для Windows / macOS / Linux / Android / iOS |
| **C++ исходники клиента** | <https://github.com/batchar2/fptn/tree/master/src/fptn-client> | GUI (Qt6) и CLI клиент |

---

## 🔧 Используемые технологии

### C++ (ядро VPN)

| Технология | Документация / Репо |
|-----------|---------------------|
| Boost | <https://www.boost.org/> |
| Conan | <https://conan.io/> |
| CMake | <https://cmake.org/> |
| protobuf | <https://protobuf.dev/> |
| spdlog | <https://github.com/gabime/spdlog> |
| fmt | <https://github.com/fmtlib/fmt> |
| jwt-cpp | <https://github.com/Thalhammer/jwt-cpp> |
| nlohmann_json | <https://github.com/nlohmann/json> |
| boringssl | <https://boringssl.googlesource.com/boringssl> |
| Qt6 (GUI клиента) | <https://www.qt.io/> |
| re2 | <https://github.com/google/re2> |
| brotli | <https://github.com/google/brotli> |
| cpp-httplib | <https://github.com/yhirose/cpp-httplib> |
| mimalloc | <https://github.com/microsoft/mimalloc> |

### Python (backend)

| Технология | Документация / Репо |
|-----------|---------------------|
| Python 3.13 | <https://docs.python.org/3.13/> |
| FastAPI | <https://fastapi.tiangolo.com/> |
| Pydantic v2 | <https://docs.pydantic.dev/latest/> |
| PyJWT | <https://pyjwt.readthedocs.io/> |
| bcrypt | <https://pypi.org/project/bcrypt/> |
| python-telegram-bot | <https://python-telegram-bot.readthedocs.io/> |
| Poetry | <https://python-poetry.org/> |
| pip-audit | <https://pypi.org/project/pip-audit/> |
| pytest | <https://docs.pytest.org/> |
| ruff | <https://docs.astral.sh/ruff/> |
| mypy | <https://mypy.readthedocs.io/> |
| black | <https://black.readthedocs.io/> |
| pylint | <https://pylint.pycqa.org/> |

### JavaScript / TypeScript (frontend)

| Технология | Документация / Репо |
|-----------|---------------------|
| React 18.3 | <https://react.dev/> |
| TypeScript 5.7 | <https://www.typescriptlang.org/> |
| Vite 8.2 | <https://vitejs.dev/> |
| Tailwind CSS 3.4 | <https://tailwindcss.com/> |
| react-router 7.18 | <https://reactrouter.com/> |
| react-i18next | <https://react.i18next.com/> |
| brotli-wasm | <https://www.npmjs.com/package/brotli-wasm> |
| lucide-react | <https://lucide.dev/> |
| vitest 5.0 | <https://vitest.dev/> |
| jsdom | <https://github.com/jsdom/jsdom> |
| ESLint | <https://eslint.org/> |
| Prettier | <https://prettier.io/> |

### Инфраструктура и DevOps

| Технология | Документация |
|-----------|--------------|
| Docker | <https://docs.docker.com/> |
| Docker Compose | <https://docs.docker.com/compose/> |
| systemd | <https://www.freedesktop.org/software/systemd/man/systemd.unit.html> |
| nginx | <https://nginx.org/en/docs/> |
| certbot (Let's Encrypt) | <https://eff-certbot.readthedocs.io/> |
| BBR (TCP congestion control) | <https://github.com/google/bbr> |
| GitHub Actions | <https://docs.github.com/en/actions> |

---

## 🔐 Безопасность и аудит

| Ресурс | URL |
|--------|-----|
| CVE Database (MITRE) | <https://cve.mitre.org/> |
| GitHub Advisory Database | <https://github.com/advisories> |
| npm audit | `npm audit` (встроенный) |
| pip-audit | `pip-audit` (PyPI) |
| Trivy (Docker CVE scanner) | <https://trivy.dev/> |
| OWASP Top 10 | <https://owasp.org/www-project-top-ten/> |

---

## 🚀 Установка на чистый сервер

| Шаг | Команда | Назначение |
|-----|---------|-----------|
| 1. prereq-install | `bash <(curl -fsSL https://raw.githubusercontent.com/ZDarow/FTPN/master/deploy/prereq-install.sh)` | Docker, Nginx, certbot, UFW |
| 2. clone | `git clone https://github.com/ZDarow/FTPN.git` | Клонирование |
| 3. deploy | `bash <(curl -fsSL .../install.sh)` | Развёртывание (3 команды) |

---

## 📡 Анти-DPI техники (для справки)

| Техника | Где описана |
|---------|-------------|
| **SNI-спуфинг** | `fptn/src/fptn-protocol-lib/censorship/strategies/` |
| **Reality mode** | `fptn/src/fptn-protocol-lib/https/methods/tls/` |
| **TLS-обфускация** | `fptn/src/fptn-protocol-lib/https/obfuscator/` |
| **Rolling Tunnel** | `fptn/src/fptn-protocol-lib/connection/strategies/rolling_tunnel/` |
| **Anti-probing** | `fptn/src/fptn-server/filter/filters/antiscan/` |

---

## 🗂️ Внутренние ссылки на документацию

| Что | Где |
|-----|-----|
| Полная техническая документация | [DOCUMENTATION.md](./DOCUMENTATION.md) |
| Аудит качества | [AUDIT.md](./AUDIT.md) |
| Аудит зависимостей | [DEPENDENCIES-AUDIT.md](./DEPENDENCIES-AUDIT.md) |
| План развёртывания | [plan.md](./plan.md) |
| Деплой на сервер | [README.md](../README.md) | 3 команды, минимальные скрипты |
| Upstream HTML-документация | [upstream/](./upstream/) |

---

## 📞 Каналы поддержки upstream

- **GitHub Issues** (оригинальный FPTN): <https://github.com/batchar2/fptn/issues>
- **GitHub Discussions**: <https://github.com/batchar2/fptn/discussions>
- **Telegram-чаты** — см. README оригинального проекта

---

*Последнее обновление: 04.09.2026*
