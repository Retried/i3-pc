"""Windows AMD/NVIDIA orchestration for the existing bench.sh/SOTC_SCRIPT capture."""
import argparse
import csv
import ctypes
from ctypes import wintypes
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import struct
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
HIDDEN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, allow_nan=False), encoding='utf-8')


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def inventory(directory):
    return {path.relative_to(directory).as_posix(): sha(path)
            for path in sorted(Path(directory).rglob('*')) if path.is_file()}


def sfo_fields(path):
    data = Path(path).read_bytes()
    if data[:4] != b'\0PSF':
        raise ValueError('Invalid SFO magic')
    _, _, keys, values, count = struct.unpack_from('<5I', data)
    result = {}
    for index in range(count):
        key_offset, fmt, size, _, offset = struct.unpack_from('<HHIII', data, 20 + index * 16)
        start = keys + key_offset
        key = data[start:data.index(b'\0', start)].decode('utf-8')
        if fmt == 0x204:
            result[key] = data[values+offset:values+offset+size].rstrip(b'\0').decode('utf-8')
    return result


def percentile(ordered, fraction):
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def metrics(path):
    values = [float(value) for value in Path(path).read_text().split()]
    if any(not math.isfinite(value) or value <= 0 for value in values):
        raise ValueError('Frame times must be positive finite milliseconds')
    # The first interval straddles the bench=on boundary in the existing capture.
    values = values[1:]
    if len(values) < 100:
        raise ValueError('Fewer than 100 measured frames')
    ordered = sorted(values)
    slowest = ordered[-max(1, math.ceil(len(values) * 0.01)):]
    return dict(frames=len(values), measured_seconds=sum(values)/1000,
                average_fps=1000/statistics.fmean(values),
                low1_fps=1000/statistics.fmean(slowest),
                median_ms=statistics.median(values), p95_ms=percentile(ordered, .95),
                p99_ms=percentile(ordered, .99), worst_ms=max(values),
                discarded_boundary_frames=1)


def assert_idle():
    if (REPO / 'HOLD').exists():
        raise RuntimeError('HOLD is set')
    output = subprocess.check_output(['tasklist.exe', '/FO', 'CSV', '/NH'], text=True, errors='replace',
                                     creationflags=HIDDEN)
    names = [row[0].lower() for row in csv.reader(output.splitlines()) if row]
    busy = [name for name in names if any(token in name for token in
            ('shadps4', 'infamous second', 'shadowofthecolossus', 'sotc_ab'))
            or name in ('i3.exe', 'clang-cl.exe', 'ninja.exe', 'cmake.exe')]
    if busy:
        raise RuntimeError('Refusing overlapping game/build work: ' + ', '.join(busy))
    class MemoryStatus(ctypes.Structure):
        _fields_ = [('length', wintypes.DWORD), ('load', wintypes.DWORD)] + [
            (name, ctypes.c_ulonglong) for name in ('total', 'available', 'page_total', 'page_available',
                                                   'virtual_total', 'virtual_available', 'extended')]
    memory = MemoryStatus(); memory.length = ctypes.sizeof(memory)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory)):
        raise RuntimeError('Cannot establish available physical memory')
    if memory.available < 8 * 1024**3:
        raise RuntimeError('Fewer than 8 GiB physical memory available before the run')


def image_base(pid):
    kernel, psapi = ctypes.WinDLL('kernel32', use_last_error=True), ctypes.WinDLL('psapi')
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    psapi.EnumProcessModules.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.HMODULE),
                                       wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    handle = kernel.OpenProcess(0x410, False, pid)
    if not handle:
        return None
    try:
        modules = (wintypes.HMODULE * 1024)()
        needed = wintypes.DWORD()
        if psapi.EnumProcessModules(handle, modules, ctypes.sizeof(modules), ctypes.byref(needed)):
            return int(modules[0])
    finally:
        kernel.CloseHandle(handle)
    return None


def copy_seed(source, target):
    target.mkdir(parents=True)
    for name in ('home', 'input_config', 'users.json', 'keys.json', 'i3_graphics.txt',
                 'i3_first_run.txt', 'i3_intro_shown.txt'):
        path = source / name
        if path.is_dir():
            shutil.copytree(path, target / name)
        elif path.is_file():
            shutil.copy2(path, target / name)
    shutil.copy2(source / 'config.json', target / 'config.json')


def snapshot_profile(source, target):
    try:
        data = source.read_bytes()
        lines = data.decode('ascii').splitlines()
        total = int(lines[0].split()[1])
        if any(len(line.split()) != 4 for line in lines[1:]):
            return False
        if sum(int(line.split()[0]) for line in lines[1:]) != total:
            return False
        target.write_bytes(data)
        return True
    except (OSError, ValueError, IndexError):
        return False


def telemetry_summary(path, start, end):
    if not path.exists():
        return None
    with path.open(encoding='utf-8-sig') as stream:
        rows = [row for row in csv.DictReader(stream)
                if start <= float(row['unix_seconds']) <= end]
    result = {'samples': len(rows), 'gpu_scope': 'whole selected NVIDIA GPU, not per-process'}
    for key in ('process_cpu_percent', 'busiest_thread_percent', 'nvidia_gpu_percent',
                'nvidia_vram_used_mb', 'working_set_mb', 'nvidia_power_w', 'nvidia_temp_c'):
        values = [float(row[key]) for row in rows if row.get(key)]
        result[key] = dict(mean=statistics.fmean(values), minimum=min(values), maximum=max(values)) if values else None
    result['gpu_frame_time_ms'] = None
    return result


def capture(args, root, hardware, scene, variant, cache, repeat, primer=False):
    assert_idle()
    label = f"{scene['name']}-{cache}-{variant['name']}-{repeat}" + ('-primer' if primer else '')
    run = root / label
    run.mkdir()
    copy_seed(root / 'seed', run / 'user')
    cache_seed = root / ('warm-seed-' + scene['name'])
    if cache == 'warm':
        shutil.copytree(cache_seed, run / 'user/cache')
    executable = run / 'shadps4.exe'
    os.link(root / 'binary/shadps4.exe', executable)
    (run / 'game_path.txt').write_text(str(args.game), encoding='utf-8')
    config = read_json(run / 'user/config.json')
    config['Vulkan'].update(gpu_id=hardware['selectedVulkanGpuIndex'], vkvalidation_enabled=False,
                            vkvalidation_core_enabled=True, vkvalidation_sync_enabled=False,
                            vkvalidation_gpu_enabled=False, vkcrash_diagnostic_enabled=False)
    config['GPU'].update(full_screen=False, present_mode='Immediate', vblank_frequency=144,
                         window_width=1920, window_height=1080,
                         internal_screen_width=1920, internal_screen_height=1080)
    config['General'].update(home_dir='', sys_modules_dir='', font_dir='', discord_rpc_enabled=False)
    write_json(run / 'user/config.json', config)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('SOTC_', 'I3_'))}
    env.update(SOTC_HEADLESS='1', I3_SKIP_FIRST_RUN='1', SOTC_SCRIPT_BOOT_MS='0', SDL_AUDIODRIVER='dummy')
    env.update(variant.get('environment', {}))
    if args.profile:
        env['SOTC_PROFILE'] = '1'
    start = scene['warmup_seconds']
    end = start + scene['duration_seconds']
    steps = list(scene.get('boot', []))
    steps += [[start-3, 'shot'], [start, 'bench=on'], [end, 'bench=off'],
              [end+2, 'shot'], [end+4, 'quit']]
    steps += [[start+offset, action] for offset, action in scene.get('route', [])]
    env['SOTC_SCRIPT'] = ','.join(f'{at}:{action}' for at, action in sorted(steps))
    metadata = dict(schema_version=1, label=label, scene=scene, variant=variant,
                    repeat=repeat, cache=cache, primer=primer, profile_enabled=args.profile,
                    driver_cache='Uncontrolled; only emulator pipeline/shader cache is reset or seeded',
                    cache_seed_hashes=inventory(cache_seed) if cache == 'warm' else {},
                    seed_manifest_sha256=sha(root / 'seed-manifest.json'),
                    executable_sha256=sha(executable), build_info=read_json(root / 'binary/build-info.json'),
                    hardware_file='hardware/diagnostics.json', emulator_settings=config,
                    environment={key: value for key, value in env.items()
                                 if key.startswith(('SOTC_', 'I3_', 'VK_')) or key == 'SDL_AUDIODRIVER'},
                    game=dict(path=str(args.game), sfo=sfo_fields(args.game.parent / 'sce_sys/param.sfo'),
                              executable_sha256=args.game_sha),
                    correctness_review='pending screenshot/log review',
                    second_pc='not available', requested_warmup_seconds=start,
                    requested_measurement_seconds=scene['duration_seconds'])
    with (run / 'stdout.log').open('wb') as stdout, (run / 'stderr.log').open('wb') as stderr:
        launched = time.time()
        process = subprocess.Popen([str(executable), '--game', str(args.game), '--fullscreen', 'false'],
                                   cwd=run, env=env, stdout=stdout, stderr=stderr, creationflags=HIDDEN)
        metadata.update(pid=process.pid, started_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        time.sleep(.5)
        metadata['image_load_base'] = image_base(process.pid)
        write_json(run / 'run.json', metadata)
        sampler_out = (run / 'telemetry.stdout.log').open('wb')
        sampler_err = (run / 'telemetry.stderr.log').open('wb')
        sampler = subprocess.Popen([args.powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                    str(root / 'harness/perfsample.ps1'), '-Out', str(run / 'telemetry.csv'),
                    '-ProcessId', str(process.pid)], stdout=sampler_out, stderr=sampler_err, creationflags=HIDDEN)
        log = run / 'user/log/shad_log.txt'
        first_flip_ms = None
        profile_snapshots = [False, False]
        window_offsets = [None, None]
        deadline = time.monotonic() + start + scene['duration_seconds'] + 150
        timed_out = False
        while process.poll() is None:
            if first_flip_ms is None and log.exists():
                match = re.search(r'first flip (\d+) ms', log.read_text(encoding='utf-8', errors='replace'))
                if match:
                    first_flip_ms = int(match[1])
            if first_flip_ms is not None and log.exists():
                for index, boundary in enumerate((start, end)):
                    if window_offsets[index] is None and time.time() >= launched + first_flip_ms/1000 + boundary:
                        window_offsets[index] = log.stat().st_size
                    if args.profile and window_offsets[index] is not None and not profile_snapshots[index]:
                        profile_snapshots[index] = snapshot_profile(run/'profile_full.txt', run/('profile-before.txt' if index == 0 else 'profile-after.txt'))
            if time.monotonic() > deadline:
                process.terminate()
                timed_out = True
                break
            time.sleep(.5)
        exit_code = process.wait()
        try:
            sampler.wait(timeout=5)
        except subprocess.TimeoutExpired:
            sampler.terminate()
            sampler.wait()
        sampler_out.close(); sampler_err.close()
    if all(value is not None for value in window_offsets):
        window = log.read_bytes()[window_offsets[0]:window_offsets[1]]
        (run / 'measurement.log').write_bytes(window)
    text = log.read_text(encoding='utf-8', errors='replace') if log.exists() else ''
    issues = []
    if timed_out or exit_code != 0:
        issues.append(f'process exit={exit_code}; timed_out={timed_out}')
    if 'App Version: 01.07' not in text or 'GPU_Model: NVIDIA' not in text:
        issues.append('target game version/GPU not confirmed in emulator log')
    if re.search(r'<Critical>|eErrorDeviceLost|Device lost|Assertion Failed', text):
        issues.append('critical/device-loss/assertion log match')
    measured = None
    try:
        measured = metrics(run / 'bench_frametimes.txt')
        if abs(measured['measured_seconds'] - scene['duration_seconds']) > max(1, scene['duration_seconds']*.05):
            issues.append('captured duration differs from requested window')
    except (OSError, ValueError) as error:
        issues.append(str(error))
    telemetry = None
    if first_flip_ms is not None:
        window_start = launched + first_flip_ms/1000 + start
        telemetry = telemetry_summary(run / 'telemetry.csv', window_start, window_start+scene['duration_seconds'])
    result = dict(label=label, scene=scene['name'], variant=variant['name'], cache=cache,
                  repeat=repeat, primer=primer, profile_enabled=args.profile,
                  status='invalid' if issues else 'captured', issues=issues, exit_code=exit_code,
                  metrics=measured, telemetry=telemetry,
                  telemetry_exit_code=sampler.returncode, log_window_byte_offsets=window_offsets,
                  profile_snapshots_complete=all(profile_snapshots) if args.profile else None,
                  frame_times_sha256=sha(run / 'bench_frametimes.txt') if (run / 'bench_frametimes.txt').exists() else None,
                  image_load_base=metadata['image_load_base'], visual_review='pending',
                  finished_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
    write_json(run / 'result.json', result)
    print(json.dumps(dict(label=label, status=result['status'], metrics=measured)), flush=True)
    if issues:
        raise RuntimeError(label + ': ' + '; '.join(issues))
    return run


def summarize(root):
    groups = {}
    excluded = []
    reviews = {}
    for path in root.glob('*/result.json'):
        result = read_json(path)
        reviews[result['label']] = result.get('visual_review', 'pending')
        if result['primer'] or result['profile_enabled'] or result['status'] != 'captured':
            excluded.append(dict(label=result['label'], primer=result['primer'],
                                 profile_enabled=result['profile_enabled'],
                                 status=result['status'], issues=result['issues']))
            continue
        key = (result['scene'], result['cache'], result['variant'])
        groups.setdefault(key, []).append(result)
    rows = []
    for (scene, cache, variant), runs in sorted(groups.items()):
        row = dict(scene=scene, cache=cache, variant=variant, repeats=len(runs))
        for key in ('average_fps', 'low1_fps', 'median_ms', 'p95_ms', 'p99_ms', 'worst_ms'):
            values = [run['metrics'][key] for run in runs]
            row[key] = dict(mean=statistics.fmean(values), minimum=min(values), maximum=max(values),
                            stdev=statistics.stdev(values) if len(values) > 1 else None)
        rows.append(row)
    comparisons = []
    for scene, cache in sorted({(row['scene'], row['cache']) for row in rows}):
        variants = {row['variant']: row for row in rows if row['scene'] == scene and row['cache'] == cache}
        if 'off' in variants and 'on' in variants:
            a, b = variants['off']['average_fps'], variants['on']['average_fps']
            delta = (b['mean']/a['mean']-1)*100
            noise = max((a['maximum']-a['minimum'])/a['mean'],
                        (b['maximum']-b['minimum'])/b['mean'])*100
            enough = min(variants['off']['repeats'], variants['on']['repeats']) >= 3
            comparisons.append(dict(scene=scene, cache=cache, average_fps_delta_percent=delta,
                                    observed_within_variant_range_percent=noise,
                                    clears_observed_range=(abs(delta) > noise) if enough else None,
                                    minimum_repeats_met=enough,
                                    acceptance='requires representative scenes, correctness and second-PC validation'))
    output = dict(groups=rows, comparisons=comparisons,
                  minimum_repeats_met=bool(rows) and all(row['repeats'] >= 3 for row in rows),
                  percentile_method='linear interpolation at (N-1)*p',
                  low1_method='1000 / mean(slowest ceil(N*0.01) intervals in milliseconds)',
                  regression_threshold='not fixed; observed repeat range is descriptive, not statistical proof',
                  second_pc='unavailable', correctness='See per-run visual reviews; no full gameplay acceptance',
                  visual_reviews=reviews, excluded_runs=excluded)
    write_json(root / 'summary.json', output)
    flat = []
    for row in rows:
        flat.append(dict(scene=row['scene'], cache=row['cache'], variant=row['variant'], repeats=row['repeats'],
                         **{key: row[key]['mean'] for key in ('average_fps', 'low1_fps', 'median_ms', 'p95_ms', 'p99_ms', 'worst_ms')}))
    if flat:
        with (root / 'summary.csv').open('w', newline='', encoding='utf-8') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(flat[0])); writer.writeheader(); writer.writerows(flat)
    markdown = ['# Local benchmark capture', '', 'Workload coverage and correctness require separate review.', '',
                '| Scene | Cache | Variant | N | Average FPS mean (range) | 1% low mean | p99 ms mean |',
                '| --- | --- | --- | --- | --- | --- | --- |']
    for row in rows:
        fps = row['average_fps']
        markdown.append(f"| {row['scene']} | {row['cache']} | {row['variant']} | {row['repeats']} | "
                        f"{fps['mean']:.2f} ({fps['minimum']:.2f}-{fps['maximum']:.2f}) | "
                        f"{row['low1_fps']['mean']:.2f} | {row['p99_ms']['mean']:.2f} |")
    markdown += ['', 'NVIDIA driver cache was not cleared. Cold/warm refer to the emulator cache.',
                 'GPU counters describe the whole NVIDIA card; GPU frame timing is unavailable.',
                 'No second-PC or full gameplay acceptance follows from this report.']
    (root/'summary.md').write_text('\n'.join(markdown)+'\n', encoding='utf-8')
    return output


def compare_suites(directories, output):
    suites = []
    for directory in directories:
        suite = read_json(directory/'suite.json')
        hardware = read_json(directory/'hardware/diagnostics.json')
        build = read_json(directory/'binary/build-info.json')
        summary = read_json(directory/'summary.json')
        cases = {(row['scene'], row['cache'], row['variant']): row for row in summary['groups']}
        suites.append(dict(path=str(directory.resolve()), machine_id=suite.get('machine_id'),
                           hardware=hardware['hardware'], build_info=build,
                           cases=cases, matrix=suite['matrix']))
    all_cases = sorted({case for suite in suites for case in suite['cases']})
    rows = []
    for case in all_cases:
        rows.append(dict(scene=case[0], cache=case[1], variant=case[2], sources=[
            dict(machine_id=suite['machine_id'], suite=suite['path'], result=suite['cases'].get(case))
            for suite in suites]))
    for suite in suites:
        suite.pop('cases')
    distinct = {suite['machine_id'] for suite in suites if suite['machine_id']}
    write_json(output, dict(suites=suites, matched_case_rows=rows, distinct_recorded_machines=len(distinct),
                           two_pc_coverage=len(distinct) >= 2,
                           note='Compare matching workload/settings/save metadata before interpreting hardware differences. Missing cases are null.'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    report = commands.add_parser('report'); report.add_argument('directory', type=Path)
    comparison = commands.add_parser('compare')
    comparison.add_argument('directories', type=Path, nargs='+')
    comparison.add_argument('--out', type=Path, required=True)
    run = commands.add_parser('run')
    run.add_argument('--executable', type=Path, required=True)
    run.add_argument('--game', type=Path)
    run.add_argument('--user-seed', type=Path, default=REPO/'dist/user')
    run.add_argument('--matrix', type=Path, required=True)
    run.add_argument('--out', type=Path, required=True)
    run.add_argument('--repeats', type=int, choices=range(1, 6), default=3)
    run.add_argument('--caches', nargs='+', choices=('cold', 'warm'), default=['cold', 'warm'])
    run.add_argument('--profile', action='store_true')
    run.add_argument('--warm-seed', type=Path, help='Reuse one same-binary, same-GPU/driver suite cache')
    run.add_argument('--powershell', default=shutil.which('powershell.exe'))
    args = parser.parse_args()
    if args.command == 'compare':
        compare_suites(args.directories, args.out); return
    if args.command == 'report':
        print(json.dumps(summarize(args.directory), indent=2)); return
    if os.name != 'nt':
        raise RuntimeError('Automatic emulator measurements target Windows only')
    assert_idle()
    args.executable = args.executable.resolve()
    args.user_seed = args.user_seed.resolve()
    args.game = (args.game or Path((REPO/'dist/game_path.txt').read_text().strip())).resolve()
    args.game_sha = sha(args.game)
    game_fields = sfo_fields(args.game.parent / 'sce_sys/param.sfo')
    if game_fields.get('APP_VER') != '01.07' or game_fields.get('TITLE_ID') != 'CUSA00004':
        raise RuntimeError('Target CUSA00004 APP_VER 01.07 is required')
    root = args.out.resolve(); root.mkdir(parents=True, exist_ok=False)
    matrix = read_json(args.matrix)
    if args.warm_seed and len(matrix['scenes']) != 1:
        raise ValueError('An external warm seed requires a single scene')
    write_json(root/'matrix.json', matrix)
    (root/'binary').mkdir()
    shutil.copy2(args.executable, root/'binary/shadps4.exe')
    info_path = args.executable.parent/'build-info.json'
    info = read_json(info_path)
    if sha(args.executable) != info['executableSha256']:
        raise RuntimeError('Executable metadata hash mismatch')
    shutil.copy2(info_path, root/'binary/build-info.json')
    pdb = args.executable.with_suffix('.pdb')
    if pdb.exists():
        shutil.copy2(pdb, root/'binary/shadps4.pdb')
    copy_seed(args.user_seed, root/'seed')
    write_json(root/'seed-manifest.json', inventory(root/'seed'))
    subprocess.run([args.powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                    str(REPO/'tools/collect-vulkan-diagnostics.ps1'), '-OutputDirectory', str(root/'hardware'),
                    '-Executable', str(root/'binary/shadps4.exe')], check=True, creationflags=HIDDEN)
    hardware = read_json(root/'hardware/diagnostics.json')
    if not hardware['hardware']['cpu'] or hardware['selectedVulkanGpuIndex'] is None:
        raise RuntimeError('AMD CPU and NVIDIA Vulkan GPU required')
    if len(hardware['hardware']['gpu']) != 1:
        raise RuntimeError('Telemetry requires one unambiguous NVIDIA GPU')
    harness = root/'harness'; harness.mkdir()
    for name in ('benchmark.py', 'perfsample.ps1', 'symprof.py', 'collect-vulkan-diagnostics.ps1'):
        shutil.copy2(REPO/'tools'/name, harness/name)
    write_json(root/'harness-manifest.json', inventory(harness))
    if 'VK_LAYER_KHRONOS_validation' in os.environ.get('VK_INSTANCE_LAYERS', ''):
        raise RuntimeError('Disable validation for timing runs')
    write_json(root/'suite.json', dict(started_at_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
               machine_id=hashlib.sha256(os.environ.get('COMPUTERNAME', 'unknown').encode()).hexdigest()[:12],
               command=sys.argv, matrix=matrix, repetitions=args.repeats, caches=args.caches,
               profile=args.profile, second_pc='unavailable', methodology='docs/BENCHMARK_PROTOCOL.md'))
    code = 1
    try:
        for scene in matrix['scenes']:
            variants = matrix.get('variants', [dict(name='baseline', environment={})])
            if 'warm' in args.caches:
                if args.warm_seed:
                    source = args.warm_seed.resolve()
                    prior_build = read_json(source.parent/'binary/build-info.json')
                    prior_hardware = read_json(source.parent/'hardware/diagnostics.json')
                    prior_suite = read_json(source.parent/'suite.json')
                    prior_scene = next((item for item in prior_suite['matrix']['scenes'] if item['name'] == scene['name']), None)
                    if prior_scene is None or any(prior_scene.get(key) != scene.get(key) for key in ('boot', 'route', 'warmup_seconds', 'duration_seconds')):
                        raise ValueError('External warm seed scene/route/window mismatch')
                    if prior_build['executableSha256'] != info['executableSha256'] or prior_hardware['hardware']['gpu'] != hardware['hardware']['gpu']:
                        raise ValueError('External warm seed binary/GPU/driver mismatch')
                    shutil.copytree(source, root/('warm-seed-'+scene['name']))
                else:
                    primer = capture(args, root, hardware, scene, variants[-1], 'cold', 0, primer=True)
                    shutil.copytree(primer/'user/cache', root/('warm-seed-'+scene['name']))
                if not inventory(root/('warm-seed-'+scene['name'])):
                    raise RuntimeError('Primer did not create a nonempty emulator cache')
            for cache in args.caches:
                for repeat in range(1, args.repeats+1):
                    order = variants if repeat % 2 else list(reversed(variants))
                    for variant in order:
                        capture(args, root, hardware, scene, variant, cache, repeat)
                        summarize(root)
        code = 0
    finally:
        summarize(root)
        write_json(root/'status.json', dict(exit_code=code, finished_at_utc=dt.datetime.now(dt.timezone.utc).isoformat()))


if __name__ == '__main__':
    main()
