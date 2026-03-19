# Migration Parity Report

Generated at: 2026-03-19T02:13:02Z

## Summary
- total scenarios: 4
- passed scenarios: 2
- failed scenarios: 2
- all strict pass: True
- all statistical pass: False

## Scenarios
- seed=42, canvas=512x512, strict=True, statistical=True
  - circle: dx=0.0415, dy=0.0347, dsize=0.0021, dfill=0.0500, dangle=69.91
  - triangle: dx=0.0167, dy=0.0437, dsize=0.0041, dfill=0.0500, dangle=7.59
  - rectangle: dx=0.1012, dy=0.0412, dsize=0.0219, dfill=0.0500, dangle=0.97
  - line: dx=0.0579, dy=0.0219, dsize=0.0111, dfill=0.0000, dangle=43.00
- seed=42, canvas=1024x1024, strict=True, statistical=True
  - circle: dx=0.0415, dy=0.0347, dsize=0.0348, dfill=0.0500, dangle=69.91
  - triangle: dx=0.0167, dy=0.0437, dsize=0.0341, dfill=0.0500, dangle=7.59
  - rectangle: dx=0.1012, dy=0.0412, dsize=0.0188, dfill=0.0500, dangle=0.97
  - line: dx=0.0579, dy=0.0219, dsize=0.0277, dfill=0.0000, dangle=43.00
- seed=1337, canvas=512x512, strict=True, statistical=False
  - statistical_failures: ['rectangle mean_y_norm delta 0.2527 > 0.2200']
  - circle: dx=0.0073, dy=0.1058, dsize=0.0015, dfill=0.0500, dangle=17.02
  - triangle: dx=0.1363, dy=0.1448, dsize=0.0121, dfill=0.0500, dangle=21.36
  - rectangle: dx=0.0137, dy=0.2527, dsize=0.0208, dfill=0.2000, dangle=36.13
  - line: dx=0.0961, dy=0.0634, dsize=0.0259, dfill=0.0500, dangle=37.56
- seed=1337, canvas=1024x1024, strict=True, statistical=False
  - statistical_failures: ['rectangle mean_y_norm delta 0.2527 > 0.2200']
  - circle: dx=0.0073, dy=0.1058, dsize=0.0357, dfill=0.0500, dangle=17.02
  - triangle: dx=0.1363, dy=0.1448, dsize=0.0303, dfill=0.0500, dangle=21.36
  - rectangle: dx=0.0137, dy=0.2527, dsize=0.0209, dfill=0.2000, dangle=36.13
  - line: dx=0.0961, dy=0.0634, dsize=0.0131, dfill=0.0500, dangle=37.56
