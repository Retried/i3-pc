"""Aggregate the existing render-thread sampler without modifying its executable."""
import argparse
import collections
import json
from pathlib import Path
import shutil
import subprocess


def read_histogram(path):
    lines = Path(path).read_text(encoding='utf-8-sig').splitlines()
    header = lines[0].split()
    if len(header) != 4 or header[0] != 'samples' or header[2] != 'outside':
        raise ValueError('Invalid sampler header')
    counts = collections.Counter()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) != 4:
            raise ValueError('Incomplete sampler row')
        counts[tuple(int(value, 16) for value in parts[1:])] += int(parts[0])
    total, outside = int(header[1]), int(header[3])
    if sum(counts.values()) != total:
        raise ValueError('Sampler histogram is incomplete')
    return total, outside, counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--exe', required=True)
    parser.add_argument('--symbolizer', default=shutil.which('llvm-symbolizer.exe'))
    parser.add_argument('--out', required=True)
    parser.add_argument('--load-base', type=lambda value: int(value, 0), required=True,
                        help='Runtime image base recorded by the benchmark runner')
    parser.add_argument('--top', type=int, default=40)
    args = parser.parse_args()
    total, outside, counts = read_histogram(args.profile)
    if not total or not args.symbolizer:
        raise ValueError('Samples and llvm-symbolizer are required')
    addresses = sorted({address for frames in counts for address in frames if address})
    if any(address < args.load_base for address in addresses):
        raise ValueError('A sampled address is below the recorded runtime image base')
    answer = subprocess.run(
        [args.symbolizer, '--obj=' + str(Path(args.exe).resolve()), '--relative-address', '-f', '-C', '-s', '--no-inlines'],
        input=''.join(f'0x{address - args.load_base:x}\n' for address in addresses), capture_output=True,
        text=True, check=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    blocks = answer.stdout.strip().split('\n\n')
    if len(blocks) != len(addresses):
        raise ValueError('Symbolizer output count does not match addresses')
    names = {address: block.splitlines()[0] for address, block in zip(addresses, blocks)}
    leaf, inclusive = collections.Counter(), collections.Counter()
    for frames, count in counts.items():
        functions = [names[address] for address in frames if address]
        leaf[functions[0] if functions else 'outside image/no scanned frame'] += count
        for function in set(functions):
            inclusive[function] += count
    def rows(histogram):
        return [dict(function=name, samples=count, percent=100 * count / total)
                for name, count in histogram.most_common(args.top)]
    result = dict(samples=total, leaf_outside_samples=outside,
                  method='Approximate stack scan: innermost three executable addresses, not an unwind',
                  interval='One completed sampler interval (approximately 10 seconds); counters reset each interval',
                  nearest_image_frame=rows(leaf), any_scanned_image_frame=rows(inclusive))
    result['unknown_nearest_frame_samples'] = leaf.get('??', 0)
    Path(args.out).write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('samples', total, 'leaf outside', outside)
    for row in result['nearest_image_frame'][:15]:
        print(f"{row['percent']:5.1f}% {row['function']}")


if __name__ == '__main__':
    main()
