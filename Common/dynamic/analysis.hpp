#pragma once
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

namespace Dynamic {
	struct Rgb {
		std::uint8_t r = 0, g = 0, b = 0;
		constexpr bool operator==(const Rgb &) const = default;
	};

	// Fixed four-level buckets prevent adjacent-neighbor chaining across gradients.
	constexpr std::uint32_t Key(Rgb c) noexcept
	{
		return (static_cast<std::uint32_t>(c.r / 4) << 12) |
			(static_cast<std::uint32_t>(c.g / 4) << 6) | (c.b / 4);
	}

	inline Rgb Representative(const std::array<Rgb, 4> &pixels,
		std::optional<Rgb> previous = {}) noexcept
	{
		std::size_t winner = 0, most = 0;
		for (std::size_t i = 0; i < pixels.size(); ++i)
		{
			std::size_t count = 0;
			for (const auto c : pixels) count += Key(c) == Key(pixels[i]);
			const bool preferred = previous && Key(pixels[i]) == Key(*previous);
			const bool wasPreferred = previous && Key(pixels[winner]) == Key(*previous);
			if (count > most || (count == most && preferred && !wasPreferred))
			{
				winner = i;
				most = count;
			}
		}
		// Return a real source pixel, never a synthesized average.
		return pixels[winner];
	}

	struct Segment {
		Rgb color;
		std::size_t start = 0, length = 0;
	};

	// A view of a top-down BGRA strip. No allocation or second image copy.
	struct Strip {
		std::span<const std::uint8_t> bytes;
		std::size_t width = 0, height = 0, stride = 0;
		bool vertical = false;

		bool Valid() const noexcept
		{
			if (width == 0 || height == 0 || width > stride / 4 ||
				height > bytes.size() / stride) return false;
			return vertical ? width == 4 : height == 4;
		}

		Rgb Read(std::size_t step, std::size_t cross) const noexcept
		{
			const auto x = vertical ? cross : step;
			const auto y = vertical ? step : cross;
			const auto offset = y * stride + x * 4;
			return { bytes[offset + 2], bytes[offset + 1], bytes[offset] };
		}
	};

	inline std::optional<Segment> Analyze(Strip strip, std::optional<Rgb> previous = {}) noexcept
	{
		if (!strip.Valid()) return {};
		const auto steps = strip.vertical ? strip.height : strip.width;
		Segment best;
		std::size_t start = 0, length = 0;
		std::uint32_t key = 0;
		const auto finish = [&]
		{
			if (!length) return;
			const bool preferred = previous && key == Key(*previous);
			const bool wasPreferred = previous && Key(best.color) == Key(*previous);
			if (length > best.length || (length == best.length && preferred && !wasPreferred))
			{
				std::array<Rgb, 4> middle;
				for (std::size_t j = 0; j < 4; ++j) middle[j] = strip.Read(start + length / 2, j);
				best = { Representative(middle, previous), start, length };
			}
		};
		for (std::size_t i = 0; i < steps; ++i)
		{
			std::array<Rgb, 4> pixels;
			for (std::size_t j = 0; j < 4; ++j) pixels[j] = strip.Read(i, j);
			const auto c = Representative(pixels, previous);
			if (length && Key(c) != key)
			{
				finish();
				length = 0;
			}
			if (!length) { start = i; key = Key(c); }
			++length;
		}
		finish();
		return best;
	}

	struct Stability {
		std::optional<Rgb> color, pending;
		std::uint64_t since = 0;

		bool Observe(std::optional<Segment> segment, std::size_t steps, std::uint64_t now) noexcept
		{
			// At least eight consecutive samples and 1% of the physical edge.
			if (!segment || segment->length < std::max<std::size_t>(8, (steps + 99) / 100))
			{
				pending.reset();
				return false;
			}
			if (color && segment->color == *color)
			{
				pending.reset();
				return false;
			}
			if (!pending || *pending != segment->color)
			{
				pending = segment->color;
				since = now;
				return false;
			}
			if (now - since < 200) return false;
			color = segment->color;
			pending.reset();
			return true;
		}
	};
}
