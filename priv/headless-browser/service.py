from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from typing import Dict , Optional
from playwright.async_api import async_playwright
import asyncio
import uuid
import base64
import time
import math
import random


app = FastAPI()
sessions: Dict[str, Dict] = {}

SESSION_DEFAULT_TIMEOUT = 300
CLEANUP_INTERVAL = 60


async def cleanup_sessions_task():
    while True:
        now = time.time()
        expired = [
            sid for sid, s in sessions.items()
            if (now - s.get("last_used", now)) > s["idle_timeout"]
        ]

        for sid in expired:
            try:
                s = sessions.get(sid)
                if s:
                    await s["context"].close()
                    print(f"🧹 Сессия {sid} закрыта из-за неактивности")
            except Exception as e:
                print(f"⚠️ Ошибка при закрытии сессии {sid}: {e}")
            finally:
                sessions.pop(sid, None)

        await asyncio.sleep(CLEANUP_INTERVAL)


def touch_session(session_id: str):
  if session_id in sessions:
      sessions[session_id]["last_used"] = time.time()



# easing (smooth step)
def _ease_in_out(t: float) -> float:
    if t < 0.5:
        return 4 * t * t * t
    else:
        return 1 - pow(-2 * t + 2, 3) / 2

async def human_like_move(page, start_x: float, start_y: float,
                          dest_x: float, dest_y: float, duration_ms: int = 400,
                          steps: int = 20):
    if steps < 2:
        steps = 2
    dt = duration_ms / steps / 1000.0
    for i in range(1, steps + 1):
        t = i / steps
        e = _ease_in_out(t)
        x = start_x + (dest_x - start_x) * e
        y = start_y + (dest_y - start_y) * e
        jitter_strength = max(0.5, 6.0 * (1 - e))
        x += random.uniform(-jitter_strength, jitter_strength)
        y += random.uniform(-jitter_strength, jitter_strength)
        await page.mouse.move(x, y)
        await asyncio.sleep(dt * (0.85 + random.random() * 0.3))

async def human_like_click(page,
                           selector: str,
                           move_duration_ms: int = 450,
                           move_steps: int = 25,
                           pre_delay_ms: int = 50,
                           post_delay_ms: int = 80,
                           press_delay_ms: int = 40,
                           button: str = "left",
                           click_count: int = 1,
                           hover_before: bool = True):
    # find element
    el = await page.query_selector(selector)
    if not el:
        raise ValueError(f"Selector not found: {selector}")

    # optionally hover (simple)
    if hover_before:
        try:
            await el.scroll_into_view_if_needed()
            await el.hover()
        except Exception:
            pass

    box = await el.bounding_box()
    if not box:
        raise ValueError("Can't get bounding box for selector: " + selector)

    # choose target point inside element (randomized)
    cx = box["x"] + box["width"] * (0.25 + random.random() * 0.5)
    cy = box["y"] + box["height"] * (0.25 + random.random() * 0.5)

    # approximate start position (Playwright не возвращает позицию мыши)
    viewport = page.viewport_size or {}
    if viewport and "width" in viewport and "height" in viewport:
        start_x = viewport["width"] / 2 + random.uniform(-100, 100)
        start_y = viewport["height"] / 2 + random.uniform(-100, 100)
    else:
        start_x = cx + random.uniform(-50, 50)
        start_y = cy + random.uniform(-50, 50)

    # move
    await human_like_move(page, start_x, start_y, cx, cy,
                          duration_ms=move_duration_ms, steps=move_steps)

    # pre-click pause
    await asyncio.sleep(pre_delay_ms / 1000.0 * (0.8 + random.random() * 0.8))

    # perform clicks (to support double click)
    for i in range(click_count):
        await page.mouse.down(button=button)
        await asyncio.sleep(press_delay_ms / 1000.0 * (0.8 + random.random() * 0.6))
        await page.mouse.up(button=button)
        # small pause between multiple clicks
        if click_count > 1:
            await asyncio.sleep(0.08 + random.random() * 0.05)

    # post-click pause
    await asyncio.sleep(post_delay_ms / 1000.0 * (0.9 + random.random() * 0.6))



@app.on_event("startup")
async def startup():
    print("🚀 Запуск Playwright...")
    app.playwright = await async_playwright().start()
    app.browser = await app.playwright.chromium.launch(headless=True)
    asyncio.create_task(cleanup_sessions_task())
    print("✅ Браузер готов.")


@app.on_event("shutdown")
async def shutdown():
    print("🛑 Остановка браузера...")
    await app.browser.close()
    await app.playwright.stop()

@app.post("/session/create")
async def create_session(width: int = 1280, height: int = 800, mobile: bool = False, locale: str = "en_US", idle_timeout: int = 600):
    context = await app.browser.new_context(
        viewport = {"width": width, "height": height},
        is_mobile = mobile,
        device_scale_factor = 1.0,
        locale = locale,
        user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        java_script_enabled = True,
        bypass_csp = True
    )
    page = await context.new_page()

    session_id = str(uuid.uuid4())
    sessions[session_id] = {"context": context, "page": page, "idle_timeout": idle_timeout, "last_used": time.time()}

    print(f"🆕 Создана сессия {session_id}")
    return {
        "session_id": session_id,
        "viewport": {"width": width, "height": height},
        "mobile": mobile,
        "locale": locale,
        "idle_timeout": idle_timeout
    }

@app.post("/session/{session_id}/run")
async def run_action(session_id: str, payload: dict):
#async def run_action(session_id: str, action: Action):
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    touch_session(session_id)
    page = sessions[session_id]["page"]

    try:
        match payload:
            # ----------------------------------------------------
            # 1 Переход на страницу
            # ----------------------------------------------------
            case {"action": "goto", "url": url}:
                print(f"🌍 Переход на {url}")
                await page.goto(url, timeout=30000, wait_until="domcontentloaded")
                # await page.wait_for_load_state("networkidle")
                return {"status": "ok", "url": url}

            # ----------------------------------------------------
            # 2 Клик с имитацией поведения пользователя
            # ----------------------------------------------------
            case {"action": "click", "selector": selector, **opts}:
                print(f"🖱️ Клик по элементу {selector}")
                if not selector:
                    raise HTTPException(status_code=400, detail="selector required for click")

                # параметры
                human = opts.get("human", False)
                button = opts.get("button", "left")  # "left" или "right"
                click_count = int(opts.get("click_count", 1))
                hover_before = bool(opts.get("hover_before", True))

                if human:
                    # безопасно вызываем human_like_click
                    await human_like_click(page,
                                            selector,
                                            move_duration_ms=int(opts.get("move_duration_ms", 450)),
                                            move_steps=int(opts.get("move_steps", 25)),
                                            pre_delay_ms=int(opts.get("pre_delay_ms", 50)),
                                            post_delay_ms=int(opts.get("post_delay_ms", 80)),
                                            press_delay_ms=int(opts.get("press_delay_ms", 40)),
                                            button=button,
                                            click_count=click_count,
                                            hover_before=hover_before)
                else:
                    # обычный клик через Playwright (поддерживаем button и clickCount)
                    await page.click(selector, button=button, click_count=click_count)

                return {"status": "ok"}

            # ----------------------------------------------------
            # 3 Ожидание появления элемента
            # ----------------------------------------------------
            case {"action": "wait", "selector": selector, **opts}:
                timeout = opts.get("timeout", 30000)
                print(f"⏳ Ожидание {selector} (timeout={timeout})")
                await page.wait_for_selector(selector, timeout=timeout)
                return {"status": "ok"}

            # ----------------------------------------------------
            # 4 Извлечение данных со страницы
            # ----------------------------------------------------
            case {"action": "extract", "selector": selector}:
                print(f"📋 Извлечение текста из {selector}")
                elements = await page.query_selector_all(selector)
                texts = [await e.inner_text() for e in elements]
                return {"result": texts}

            # ----------------------------------------------------
            # 5  Заполнение поля формы
            # ----------------------------------------------------
            case {"action": "fill", "selector": selector, "value": value}:
                await page.fill(selector, value)
                return {"status": "ok"}

            # ----------------------------------------------------
            # 6 Выполнение произвольного JS-кода в контексте страницы
            # ----------------------------------------------------
            case {"action": "evaluate", "script": script}:
                print(f"⚙️ Выполнение JS-скрипта: {script[:50]}...")
                result = await page.evaluate(script)
                return {"result": result}

            # ----------------------------------------------------
            # 7 Скриншот страницы или элемента
            # ----------------------------------------------------
            case {"action": "screenshot", **opts}:
                print(f"📸 Создание скриншота...")
                # опциональные параметры:
                # selector - если задан, сделаем скриншот элемента
                # full_page - true/false (строка "true"/"false" из JSON or boolean)
                # type - "png" или "jpeg"
                selector = opts.get("selector", None)
                full_page = opts.get("full_page", None)
                img_type = opts.get("type", None) or "png"
                quality = opts.get("quality", None)

                kwargs = {}

                if img_type not in ("png", "jpeg"):
                    img_type = "png"
                kwargs["type"] = img_type

                if quality:
                    kwargs["quality"] = quality

                if full_page is not None:
                    # JSON может прислать true/false
                    kwargs["full_page"] = bool(full_page)
                # снять со страницы или с элемента
                if selector:
                    el = await page.query_selector(selector)
                    if not el:
                        raise HTTPException(status_code=404, detail="Selector not found")
                    img_bytes = await el.screenshot(**kwargs)
                else:
                    img_bytes = await page.screenshot(**kwargs)

                b64 = base64.b64encode(img_bytes).decode("ascii")
                return {"image_data": b64}


            # ----------------------------------------------------
            #  Неизвестное действие
            # ----------------------------------------------------
            case _:
                print(f"❓ Неизвестный action: {payload}")
                raise HTTPException(status_code=400, detail=f"Unknown action: {payload}")

    except Exception as e:
        print(f"⚠️ Ошибка при выполнении {payload.get('action')}: {e}")
        raise HTTPException(status_code=500, detail=str(e))



#         elif act == "fill" and request["selector"] and request["value"] is not None:
#             await page.fill(request["selector"], request["value"])
#             return {"status": "ok"}


@app.post("/session/{session_id}/close")
async def close_session(session_id: str):
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    try:
        await sessions[session_id]["context"].close()
        del sessions[session_id]
        print(f"❌ Сессия {session_id} закрыта вручную")
        return {"status": "closed"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

