"""Resolve paths and exact frame/sample clocks from a studio document."""
import dataclasses
import fractions
import json
import pathlib


def rate(value):
    if not isinstance(value, (list, tuple)) or len(value) != 2 or any(type(v) is not int or v <= 0 for v in value):
        raise ValueError('rate must be two positive integers')
    fraction = fractions.Fraction(*value)
    return fraction.numerator, fraction.denominator


def snap(value):
    """Round half up, including negative values, without binary-float ties."""
    value = fractions.Fraction(str(value))
    return (value.numerator * 2 + value.denominator) // (2 * value.denominator)


def frame_at(seconds, fps):
    return snap(fractions.Fraction(str(seconds)) * fractions.Fraction(*fps))


@dataclasses.dataclass
class Timeline:
    root: pathlib.Path
    episode: pathlib.Path
    cut: str
    config: dict
    resolved: dict
    rate: tuple
    width: int
    height: int

    @classmethod
    def load(cls, root, config, short=False, require_resolved=True):
        root = pathlib.Path(root).resolve()
        episode = root / config.get('short_episode' if short else 'episode', 'studio/short.json' if short else 'studio/episode.json')
        document = json.loads(episode.read_text())
        cut = config.get('short_cut' if short else 'cut', 'full')
        settings = document['cuts'][cut]
        if not isinstance(cut, str) or pathlib.Path(cut).name != cut or cut in ('.', '..'):
            raise ValueError('cut must be a single directory name')
        if settings.get('sr', 48000) != 48000:
            raise ValueError('studio audio currently requires 48000 Hz')
        stem = '' if episode.stem == 'episode' else episode.stem + '.'
        path = episode.parent / 'build' / cut / (stem + 'timeline.resolved.json')
        resolved = json.loads(path.read_text()) if path.exists() and require_resolved else {}
        if require_resolved and not resolved:
            raise ValueError(f'resolve the cut before using {path}')
        fps = rate(resolved.get('rate', settings['rate']))
        if 'rate' in resolved and fps != rate(settings['rate']):
            raise ValueError(f'stale resolved frame rate: {path}')
        if any(type(settings[k]) is not int or settings[k] <= 0 for k in ('w', 'h')):
            raise ValueError('cut dimensions must be positive integers')
        if resolved and any(resolved.get(k, settings.get(k,48000)) != settings.get(k,48000) for k in ('w', 'h', 'sr')):
            raise ValueError(f'stale resolved geometry or sample rate: {path}')
        return cls(root, episode, cut, settings, resolved, fps,
                   resolved.get('w', settings['w']), resolved.get('h', settings['h']))

    @property
    def prefix(self):
        return '' if self.episode.stem == 'episode' else self.episode.stem + '.'

    def output(self, name):
        return self.episode.parent / 'build' / self.cut / (self.prefix + name)

    @property
    def resolved_path(self):
        return self.output('timeline.resolved.json')

    @property
    def frames(self):
        return self.resolved['frames']

    @property
    def timecode(self):
        return self.resolved.get('tc_start', self.config.get('tc_start', '00:00:00:00'))

    def seconds(self, frame):
        return fractions.Fraction(frame * self.rate[1], self.rate[0])

    def samples(self, frames=None):
        value = self.seconds(self.frames if frames is None else frames) * self.config.get('sr', 48000)
        if value.denominator != 1:
            raise ValueError('cut duration is not a whole number of audio samples')
        return value.numerator


def delivery(config, role='master'):
    settings = dict(config.get('delivery', {}).get(role, {}))
    fmt = settings.setdefault('format', 'mp4')
    if fmt not in ('mp4', 'mov'):
        raise ValueError('delivery format must be mp4 or mov')
    if settings.get('edit_lists') is False:
        if fmt != 'mov':
            raise ValueError('strict no-edit delivery requires MOV')
        settings.setdefault('audio_codec', 'pcm')
        if settings['audio_codec'] != 'pcm':
            raise ValueError('strict no-edit delivery requires PCM audio')
    return settings
