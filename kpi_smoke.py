#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WOOF-KNOW (СПРИ) — kpi_smoke.py
Назначение: e2e‑проверка /health и /v1/query, сбор простых KPI:
- error_rate
- p50/p95 latency (мс)
- hit_rate@k (по признаку count>0 и no_answer=false)
- доля "нет ответа"
- net-positive (по feedback, если включено)

Требования:
- Python 3.11+
- pip install requests

Пример запуска:
  python kpi_smoke.py --base-url http://localhost:8080 \
      --token "Bearer <JWT>" \
      --q "Каковы KPI MVP?" \
      --k 10 --threshold 0.8 \
      --n 25 --warmup 3 --feedback

Выход:
- Резюме в stdout (русский язык)
- (опция) CSV с сырыми измерениями
"""
from __future__ import annotations
import argparse
import csv
import json
import os
import sys
import time
from dataclasses import dataclass
from statistics import median
from typing import List, Optional

import requests

@dataclass
class Sample:
    ok: bool
    status: int
    latency_ms: int
    count: Optional[int]
    no_answer: Optional[bool]
    feedback: Optional[int]


def p95(values: List[float]) -> float:
    if not values:
        return float('nan')
    s = sorted(values)
    # nearest-rank method
    k = max(1, int(0.95 * len(s)))
    return float(s[k - 1])


def check_health(base_url: str, headers: dict) -> None:
    url = f"{base_url.rstrip('/')}/v1/health"
    r = requests.get(url, headers=headers, timeout=10)
    r.raise_for_status()


def run_query(base_url: str, headers: dict, q: str, k: int, threshold: float, show_sources: bool, allow_external: bool) -> Sample:
    url = f"{base_url.rstrip('/')}/v1/query"
    payload = {
        "q": q,
        "k": k,
        "threshold": threshold,
        "show_sources": show_sources,
        "allow_external_context": allow_external,
    }
    t0 = time.perf_counter()
    r = requests.post(url, headers=headers, json=payload, timeout=65)
    dt_ms = int((time.perf_counter() - t0) * 1000)
    ok = r.status_code == 200
    count = None
    no_answer = None
    if ok:
        try:
            data = r.json()
            count = int(data.get("count")) if data.get("count") is not None else None
            no_answer = bool(data.get("no_answer")) if data.get("no_answer") is not None else None
        except Exception:
            ok = False
    return Sample(ok=ok, status=r.status_code, latency_ms=dt_ms, count=count, no_answer=no_answer, feedback=None)


def send_feedback(base_url: str, headers: dict, qid: str, value: int) -> bool:
    url = f"{base_url.rstrip('/')}/v1/feedback"
    payload = {"qid": qid, "value": value}
    try:
        r = requests.post(url, headers=headers, json=payload, timeout=10)
        return r.status_code == 200
    except Exception:
        return False


def main() -> int:
    ap = argparse.ArgumentParser(description="СПРИ — E2E KPI smoke-тест")
    ap.add_argument('--base-url', default=os.getenv('SPREE_BASE_URL', 'http://localhost:8080'))
    ap.add_argument('--token', default=os.getenv('SPREE_TOKEN', ''))
    ap.add_argument('--q', default=os.getenv('SPREE_QUERY', 'Каковы KPI MVP?'))
    ap.add_argument('--k', type=int, default=int(os.getenv('SPREE_K', '10')))
    ap.add_argument('--threshold', type=float, default=float(os.getenv('SPREE_THRESHOLD', '0.8')))
    ap.add_argument('--n', type=int, default=int(os.getenv('SPREE_N', '20')), help='Количество запросов после прогрева')
    ap.add_argument('--warmup', type=int, default=int(os.getenv('SPREE_WARMUP', '3')))
    ap.add_argument('--show-sources', action='store_true')
    ap.add_argument('--allow-external', action='store_true')
    ap.add_argument('--csv', default=os.getenv('SPREE_CSV', ''))
    ap.add_argument('--feedback', action='store_true', help='Отправлять feedback=+1 при успешном ответе')
    args = ap.parse_args()

    headers = {"Accept": "application/json"}
    if args.token:
        # Поддержка как уже готового "Bearer ...", так и сырого JWT
        headers["Authorization"] = args.token if args.token.lower().startswith("bearer ") else f"Bearer {args.token}"

    # /health
    try:
        check_health(args.base_url, headers)
    except Exception as e:
        print(f"❌ Health-check провален: {e}")
        return 2

    # Прогрев
    for _ in range(max(0, args.warmup)):
        try:
            run_query(args.base_url, headers, args.q, args.k, args.threshold, args.show_sources, args.allow_external)
        except Exception:
            pass

    # Основные замеры
    samples: List[Sample] = []
    for i in range(max(1, args.n)):
        try:
            s = run_query(args.base_url, headers, args.q, args.k, args.threshold, args.show_sources, args.allow_external)
            samples.append(s)
        except Exception as e:
            samples.append(Sample(ok=False, status=-1, latency_ms=0, count=None, no_answer=None, feedback=None))
        time.sleep(0.05)  # минимальная пауза, чтобы не удариться в rate-limit локально

    # Подсчёты
    lat_ok = [s.latency_ms for s in samples if s.ok]
    err = [s for s in samples if not s.ok]
    total = len(samples)
    error_rate = round(100.0 * len(err) / total, 2)
    p50 = int(median(lat_ok)) if lat_ok else None
    p95_ms = int(p95(lat_ok)) if lat_ok else None

    hits = [s for s in samples if s.ok and (s.count is not None and s.count > 0) and not bool(s.no_answer)]
    hit_rate = round(100.0 * len(hits) / total, 2)
    no_answer_cnt = len([s for s in samples if s.ok and bool(s.no_answer)])
    no_answer_pct = round(100.0 * no_answer_cnt / total, 2)

    # CSV (по желанию)
    if args.csv:
        with open(args.csv, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(["ok", "status", "latency_ms", "count", "no_answer"]) 
            for s in samples:
                w.writerow([int(s.ok), s.status, s.latency_ms, s.count if s.count is not None else '', int(s.no_answer) if s.no_answer is not None else ''])

    # Вывод
    print("\n==== СПРИ — KPI Smoke (резюме) ====")
    print(f"База: {args.base_url}")
    print(f"Запросов: {total} (прогрев: {args.warmup})")
    print(f"Ошибка: {error_rate}% ({len(err)}/{total})")
    if p50 is not None and p95_ms is not None:
        print(f"Latency p50: {p50} мс; p95: {p95_ms} мс (цель: ≤ 7000–10000 мс)")
    print(f"Hit-rate@{args.k}: {hit_rate}% (эвристика: count>0 & !no_answer)")
    print(f"Доля 'нет ответа': {no_answer_pct}%")

    # Простая оценка KPI
    kpi_ok = True
    if p95_ms is None or p95_ms > 10000:
        print("⚠️  P95 выше целевого 10 с")
        kpi_ok = False
    if hit_rate < 70.0:
        print("⚠️  Hit-rate ниже 70%")
        kpi_ok = False
    if no_answer_pct > 20.0:
        print("⚠️  'Нет ответа' выше 20%")
        kpi_ok = False

    print("Итог KPI:", "✅ соответствует" if kpi_ok else "❌ не соответствует")

    return 0 if kpi_ok else 1


if __name__ == '__main__':
    sys.exit(main())
