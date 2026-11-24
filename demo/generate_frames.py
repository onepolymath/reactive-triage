#!/usr/bin/env python3
"""Render the silent storyboard frames used in the demo video."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent / "frames"
W, H = 1920, 1080
BG = (11, 18, 16)
CARD = (20, 32, 28)
INK = (232, 245, 239)
MUTED = (157, 184, 174)
ACCENT = (61, 214, 140)
WARN = (255, 176, 32)
BAD = (255, 107, 107)
LINE = (42, 61, 54)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def new_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, W, 8), fill=ACCENT)
    draw.text((80, 40), "TRIAGE  ·  REACTIVE OMNI BUILDATHON", font=font(22), fill=ACCENT)
    return img, draw


def rounded(draw: ImageDraw.ImageDraw, box, fill, outline=LINE, radius=24, width=2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def save(img: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    img.save(path, "PNG")
    print("wrote", path)


def frame_title() -> None:
    img, draw = new_canvas()
    draw.text((80, 280), "Triage", font=font(140, True), fill=INK)
    draw.text((80, 460), "Leave a clerk watching your approvals.", font=font(48), fill=MUTED)
    draw.text((80, 620), "Base Sepolia  →  Lasna react()  →  Base Sepolia callback  →  policy verdict", font=font(32), fill=ACCENT)
    draw.text((80, 940), "Testnet only  ·  Reactive Meets AI", font=font(28), fill=MUTED)
    save(img, "01-title.png")


def frame_architecture() -> None:
    img, draw = new_canvas()
    draw.text((80, 120), "The loop", font=font(72, True), fill=INK)
    boxes = [
        (80, 280, 520, 560, "1  Origin", "DemoToken\nBase Sepolia\nTransfer / Approval"),
        (540, 280, 980, 560, "2  Reactive", "TriageReactive\nLasna\ndecode + score"),
        (1000, 280, 1440, 560, "3  Callback", "TriageDesk\nBase Sepolia\nopenCase"),
        (1460, 280, 1840, 560, "4  Policy", "Agent in the loop\nrecord / watch\nor escalate"),
    ]
    for x0, y0, x1, y1, title, body in boxes:
        rounded(draw, (x0, y0, x1, y1), CARD)
        draw.text((x0 + 32, y0 + 36), title, font=font(32, True), fill=ACCENT)
        draw.text((x0 + 32, y0 + 110), body, font=font(28), fill=INK)
    for i, x in enumerate((520, 980, 1440)):
        draw.polygon([(x + 4, 400), (x + 20, 420), (x + 4, 440)], fill=ACCENT)
    save(img, "02-architecture.png")


def frame_origin() -> None:
    img, draw = new_canvas()
    draw.text((80, 120), "Origin event", font=font(72, True), fill=INK)
    draw.text((80, 220), "Base Sepolia  ·  DemoToken.approve(spender, type(uint256).max)", font=font(32), fill=MUTED)
    rounded(draw, (80, 320, 1840, 860), CARD)
    lines = [
        ("kind", "Approval"),
        ("owner", "0x1111…1111"),
        ("spender", "0x3333…3333"),
        ("amount", "2^256 - 1   (unlimited)"),
        ("why it matters", "This is the classic approval foot-gun."),
    ]
    y = 360
    for key, value in lines:
        draw.text((120, y), key, font=font(28), fill=MUTED)
        draw.text((520, y), value, font=font(32, True), fill=INK)
        y += 90
    save(img, "03-origin.png")


def frame_react() -> None:
    img, draw = new_canvas()
    draw.text((80, 120), "Lasna  ·  react()", font=font(72, True), fill=INK)
    draw.text((80, 220), "TriageReactive scores the log before requesting the callback.", font=font(32), fill=MUTED)
    rounded(draw, (80, 340, 900, 860), CARD)
    draw.text((120, 380), "On-chain score", font=font(28), fill=MUTED)
    draw.text((120, 450), "90 / 100", font=font(96, True), fill=BAD)
    draw.text((120, 600), "suggested action: escalate", font=font(32), fill=BAD)
    rounded(draw, (980, 340, 1840, 860), CARD)
    body = "if amount >= uint128.max\n    score = 90\nrequestCallbackV_1_0(\n    openCase(address(0), …)\n)\n# mismatches return, they do not revert"
    draw.text((1020, 400), body, font=font(32), fill=INK)
    save(img, "04-react.png")


def frame_callback() -> None:
    img, draw = new_canvas()
    draw.text((80, 120), "Callback  ·  openCase", font=font(72, True), fill=INK)
    draw.text((80, 220), "Proxy injects the reactive address into the first payload word.", font=font(32), fill=MUTED)
    rounded(draw, (80, 340, 1840, 880), CARD)
    rows = [
        ("msg.sender", "Base Sepolia callback proxy  0x476F…3585", ACCENT),
        ("injected sender", "TriageReactive (must match the desk constructor)", ACCENT),
        ("case id", "4", INK),
        ("kind / score", "Approval  ·  90", BAD),
        ("status", "CaseOpened  ·  waiting for a verdict", WARN),
    ]
    y = 380
    for key, value, color in rows:
        draw.text((120, y), key, font=font(28), fill=MUTED)
        draw.text((620, y), value, font=font(32, True), fill=color)
        y += 90
    save(img, "05-callback.png")


def frame_verdict() -> None:
    img, draw = new_canvas()
    draw.text((80, 120), "Policy agent", font=font(72, True), fill=INK)
    draw.text((80, 220), "The agent is part of the running system. An LLM may only rewrite the rationale.", font=font(32), fill=MUTED)
    rounded(draw, (80, 340, 1840, 880), CARD)
    draw.text((120, 390), "fileVerdict(4, 90, ESCALATE, heuristic-v1, …)", font=font(36, True), fill=INK)
    quote = (
        "Unlimited approval from 0x1111… to spender 0x3333…\n"
        "This is the classic 'set and forget' foot-gun;\n"
        "escalate so the owner can revoke it."
    )
    draw.text((120, 500), quote, font=font(32), fill=MUTED)
    draw.text((120, 760), "Action is decided before any API call.", font=font(28), fill=ACCENT)
    save(img, "06-verdict.png")


def frame_alert() -> None:
    img, draw = new_canvas()
    draw.text((80, 120), "AlertRaised", font=font(72, True), fill=BAD)
    draw.text((80, 220), "The desk emits an event a wallet, a bot, or a Safe owner can watch.", font=font(32), fill=MUTED)
    rounded(draw, (80, 360, 1840, 820), (48, 22, 22), outline=BAD)
    draw.text((120, 430), "CASE 4   ·   UNLIMITED APPROVAL", font=font(36, True), fill=BAD)
    draw.text((120, 530), "subject     0x1111…1111", font=font(32), fill=INK)
    draw.text((120, 600), "spender     0x3333…3333", font=font(32), fill=INK)
    draw.text((120, 700), "Leave the clerk running. You do not have to babysit every log.", font=font(32), fill=MUTED)
    save(img, "07-alert.png")


def frame_tests() -> None:
    img, draw = new_canvas()
    draw.text((80, 120), "Tests pass locally", font=font(72, True), fill=INK)
    rounded(draw, (80, 280, 1840, 880), CARD)
    body = (
        "forge test --no-dynamic-test-linking\n"
        "  TriageTest        15 passed\n"
        "  TriageScoreTest    5 passed\n"
        "\n"
        "python3 -m unittest discover -s services/policy/tests\n"
        "  7 passed\n"
        "\n"
        "Live hashes belong in deployments/loop.json\n"
        "once the throwaway testnet address is faucet-funded."
    )
    draw.text((120, 330), body, font=font(36), fill=INK)
    save(img, "08-tests.png")


def main() -> None:
    frame_title()
    frame_architecture()
    frame_origin()
    frame_react()
    frame_callback()
    frame_verdict()
    frame_alert()
    frame_tests()


if __name__ == "__main__":
    main()
