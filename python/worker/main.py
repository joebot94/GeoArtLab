from __future__ import annotations

import json
import sys
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from core import (
    ensure_output_root,
    export_animation,
    export_piece,
    generate_seed_sequence,
    normalize_canvas,
    normalize_render_params,
    render_animation_preview,
    render_preview,
)

DEFAULT_OUTPUT_ROOT = str(Path.home() / "JBT" / "geo_art_lab")


class ExportCancelledError(RuntimeError):
    pass


@dataclass
class WorkerState:
    active_export_request_id: str | None = None
    active_animation_request_id: str | None = None
    cancel_active_export: bool = False


state = WorkerState()


def send_message(message: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def send_success(request_id: str | None, message_type: str, payload: dict[str, Any] | None = None) -> None:
    message: dict[str, Any] = {
        "type": message_type,
        "ok": True,
        "payload": payload or {},
    }
    if request_id is not None:
        message["request_id"] = request_id
    send_message(message)


def send_error(request_id: str | None, message: str, details: Any | None = None) -> None:
    payload: dict[str, Any] = {"message": message}
    if details is not None:
        payload["details"] = details

    error_message: dict[str, Any] = {
        "type": "error",
        "ok": False,
        "error": payload,
    }
    if request_id is not None:
        error_message["request_id"] = request_id
    send_message(error_message)


def handle_hello(request_id: str | None) -> None:
    send_success(
        request_id,
        "ready",
        {
            "app": "GeoArtLab",
            "protocol": "jsonl-stdio-v1",
            "capabilities": [
                "render_preview",
                "export_batch",
                "render_animation_preview",
                "export_animation",
                "cancel",
                "ping",
            ],
        },
    )


def handle_ping(request_id: str | None) -> None:
    send_success(request_id, "ready", {"status": "pong"})


def handle_cancel(request_id: str | None, payload: dict[str, Any]) -> None:
    target_request_id = payload.get("target_request_id")

    if target_request_id and (
        target_request_id == state.active_export_request_id or target_request_id == state.active_animation_request_id
    ):
        state.cancel_active_export = True
    elif target_request_id is None and (
        state.active_export_request_id is not None or state.active_animation_request_id is not None
    ):
        state.cancel_active_export = True

    send_success(request_id, "ready", {"cancel_requested": bool(state.cancel_active_export)})


def handle_render_preview(request_id: str | None, payload: dict[str, Any]) -> None:
    params = payload.get("params") or {}
    canvas = payload.get("canvas") or {}
    output_root = payload.get("output_root") or DEFAULT_OUTPUT_ROOT

    result = render_preview(
        output_root=output_root,
        render_params=params,
        canvas=canvas,
    )
    send_success(request_id, "preview_ready", result)


def handle_render_animation_preview(request_id: str | None, payload: dict[str, Any]) -> None:
    params = payload.get("params") or {}
    canvas = payload.get("canvas") or {}
    timeline = payload.get("timeline") or {}
    frame = int(payload.get("frame", 0))
    output_root = payload.get("output_root") or DEFAULT_OUTPUT_ROOT

    result = render_animation_preview(
        output_root=output_root,
        render_params=params,
        canvas=canvas,
        timeline=timeline,
        frame=frame,
    )
    send_success(request_id, "animation_preview_ready", result)


def handle_export_batch(request_id: str | None, payload: dict[str, Any]) -> None:
    if request_id is None:
        raise ValueError("export_batch requires request_id")

    render_params = payload.get("render") or {}
    canvas = payload.get("canvas") or {}
    base_seed = int(payload.get("base_seed", 42))
    repeats = max(1, int(payload.get("repeats", 1)))
    output_root = payload.get("output_root") or DEFAULT_OUTPUT_ROOT

    normalized_render = normalize_render_params(render_params)
    export_max = int(normalized_render["canvas_meta"].get("export_max_dim", 16384))
    normalized_canvas = normalize_canvas(canvas, max_dimension=export_max)
    out_root = ensure_output_root(output_root)
    seeds = generate_seed_sequence(base_seed, repeats)

    items: list[dict[str, Any]] = []

    state.active_export_request_id = request_id
    state.cancel_active_export = False

    try:
        for idx, seed in enumerate(seeds):
            if state.cancel_active_export:
                raise ExportCancelledError("Export cancelled by client")

            item = export_piece(
                output_root=out_root,
                render_params=normalized_render,
                canvas=normalized_canvas,
                seed=seed,
                repeat_index=idx,
            )
            items.append(item)

            send_message(
                {
                    "type": "export_progress",
                    "ok": True,
                    "payload": {
                        "request_id": request_id,
                        "completed": idx + 1,
                        "total": len(seeds),
                        "seed": seed,
                        "base_name": item["base_name"],
                    },
                }
            )

        compact_items = [
            {
                "base_name": item["base_name"],
                "seed": item["seed"],
                "repeat_index": item["repeat_index"],
                "png_path": item["png_path"],
                "svg_path": item["svg_path"],
                "jbt_path": item["jbt_path"],
            }
            for item in items
        ]

        send_success(
            request_id,
            "export_complete",
            {
                "items": compact_items,
                "output_root": str(out_root),
                "total": len(compact_items),
            },
        )
    finally:
        state.active_export_request_id = None
        state.cancel_active_export = False


def handle_export_animation(request_id: str | None, payload: dict[str, Any]) -> None:
    if request_id is None:
        raise ValueError("export_animation requires request_id")

    render_params = payload.get("render") or {}
    canvas = payload.get("canvas") or {}
    timeline = payload.get("timeline") or {}
    animation_name = payload.get("animation_name")
    output_root = payload.get("output_root") or DEFAULT_OUTPUT_ROOT

    state.active_animation_request_id = request_id
    state.cancel_active_export = False

    def progress(completed: int, total: int, frame: int, frame_name: str) -> None:
        if state.cancel_active_export:
            raise ExportCancelledError("Export cancelled by client")

        send_message(
            {
                "type": "animation_export_progress",
                "ok": True,
                "payload": {
                    "request_id": request_id,
                    "completed": completed,
                    "total": total,
                    "frame": frame,
                    "frame_name": frame_name,
                },
            }
        )

    try:
        result = export_animation(
            output_root=output_root,
            render_params=render_params,
            canvas=canvas,
            timeline=timeline,
            animation_name=animation_name,
            progress_cb=progress,
        )
        send_success(request_id, "animation_export_complete", result)
    finally:
        state.active_animation_request_id = None
        state.cancel_active_export = False


def handle_request(request: dict[str, Any]) -> None:
    request_id = request.get("request_id")
    message_type = request.get("type")
    payload = request.get("payload")

    if not isinstance(message_type, str):
        raise ValueError("Request missing string field 'type'")
    if payload is None:
        payload = {}
    if not isinstance(payload, dict):
        raise ValueError("Request payload must be an object")

    if message_type == "hello":
        handle_hello(request_id)
        return
    if message_type == "ping":
        handle_ping(request_id)
        return
    if message_type == "cancel":
        handle_cancel(request_id, payload)
        return
    if message_type == "render_preview":
        handle_render_preview(request_id, payload)
        return
    if message_type == "render_animation_preview":
        handle_render_animation_preview(request_id, payload)
        return
    if message_type == "export_batch":
        handle_export_batch(request_id, payload)
        return
    if message_type == "export_animation":
        handle_export_animation(request_id, payload)
        return

    raise ValueError(f"Unsupported request type: {message_type}")


def process_stdin() -> None:
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue

        try:
            parsed = json.loads(line)
            if not isinstance(parsed, dict):
                raise ValueError("Request must be a JSON object")
            handle_request(parsed)
        except ExportCancelledError as exc:
            request_id = None
            try:
                maybe_req = json.loads(line)
                if isinstance(maybe_req, dict):
                    request_id = maybe_req.get("request_id")
            except Exception:
                pass
            send_error(request_id, str(exc))
        except Exception as exc:
            request_id = None
            details = None
            try:
                maybe_req = json.loads(line)
                if isinstance(maybe_req, dict):
                    request_id = maybe_req.get("request_id")
            except Exception:
                details = {"raw_line": line[:200]}

            error_details = {"exception": exc.__class__.__name__}
            if details:
                error_details.update(details)

            send_error(request_id, str(exc), error_details)
            traceback.print_exc(file=sys.stderr)
            sys.stderr.flush()


def main() -> int:
    process_stdin()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
