#include "dynamic/analysis.hpp"
#include "dynamic/burst.hpp"
#include "dynamic/transition.hpp"
#include "config/appearanceaccent.hpp"
#include "dynamic/geometry.hpp"
#include <cstdlib>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

namespace {
	using Dynamic::Rgb;
	constexpr Rgb red{ 240, 0, 0 }, blue{ 0, 0, 240 }, green{ 0, 240, 0 };
	unsigned checks = 0;
	void Check(bool condition, const char *name)
	{
		++checks;
		if (!condition) throw std::runtime_error(name);
	}
	struct Image {
		std::vector<std::uint8_t> bytes;
		std::size_t width, height;
		bool vertical;
		explicit Image(const std::vector<Rgb> &steps, bool v = false) :
			bytes(steps.size() * 16), width(v ? 4 : steps.size()), height(v ? steps.size() : 4), vertical(v)
		{
			for (std::size_t i = 0; i < steps.size(); ++i)
			{
				for (std::size_t j = 0; j < 4; ++j)
				{
					const auto pos = ((v ? i : j) * width + (v ? j : i)) * 4;
					bytes[pos] = steps[i].b; bytes[pos + 1] = steps[i].g; bytes[pos + 2] = steps[i].r;
				}
			}
		}
		Dynamic::Strip View() const { return { bytes, width, height, width * 4, vertical }; }
	};

	// Exhaustively enumerate contiguous intervals for an independent small-image oracle.
	Dynamic::Segment Oracle(const std::vector<Rgb> &pixels, std::optional<Rgb> previous)
	{
		Dynamic::Segment best;
		for (std::size_t a = 0; a < pixels.size(); ++a)
		{
			for (std::size_t b = a; b < pixels.size(); ++b)
			{
				bool same = true;

				for (auto i = a; i <= b; ++i)
				{
					same &= Dynamic::Key(pixels[i]) == Dynamic::Key(pixels[a]);

				}
				if (!same) continue;
				const auto n = b - a + 1;
				const bool preferred = previous && Dynamic::Key(pixels[a]) == Dynamic::Key(*previous);
				const bool oldPreferred = previous && Dynamic::Key(best.color) == Dynamic::Key(*previous);
				if (n > best.length || (n == best.length && preferred && !oldPreferred))
					best = { pixels[a + n / 2], a, n };
			}
		}
		return best;
	}
}

int main()
{
	try {
		Check(Dynamic::Representative({ red, red, blue, blue }) == red, "2:2 first sample");
		Check(Dynamic::Representative({ red, red, blue, blue }, blue) == blue, "2:2 previous bucket");
		Check(Dynamic::Representative({ red, green, blue, blue }, red) == blue, "majority beats history");
		Check(Dynamic::Representative({ Rgb{4,5,6}, Rgb{7,6,5}, red, blue }) == Rgb{4,5,6}, "exact source pixel in winning bucket");
		std::vector<Rgb> t2(300, red);
		t2.insert(t2.end(), 450, blue); t2.insert(t2.end(), 300, red);
		for (bool vertical : { false, true })
		{
			const auto result = Dynamic::Analyze(Image(t2, vertical).View());
			Check(result && result->color == blue && result->start == 300 && result->length == 450,
				"continuity must beat global frequency in both orientations");
		}
		std::vector<Rgb> gradient;
		for (unsigned c = 0; c < 256; ++c) gradient.push_back({ static_cast<std::uint8_t>(c), 0, 0 });
		Check(Dynamic::Analyze(Image(gradient).View())->length == 4, "gradient cannot chain");
		Check(!Dynamic::Analyze({ {}, 4, 20, 16, true }), "truncated image rejected");
		Check(!Dynamic::Analyze({ {}, 1, 1, 0, false }), "zero stride rejected");
		std::mt19937 random(1338);
		for (unsigned trial = 0; trial < 1000; ++trial)
		{
			std::vector<Rgb> values;
			for (unsigned i = 0, n = 1 + random() % 40; i < n; ++i)
			{
				const auto c = static_cast<std::uint8_t>((random() % 4) * 8 + random() % 4);
				values.push_back({c,c,c});
			}
			const std::optional<Rgb> previous = trial % 2 ? std::optional<Rgb>(values.back()) : std::nullopt;
			const auto expected = Oracle(values, previous);
			for (bool vertical : { false, true })
			{
				const auto result = Dynamic::Analyze(Image(values, vertical).View(), previous);
				Check(result && result->start == expected.start && result->length == expected.length &&
					result->color == expected.color, "randomized exhaustive oracle");
			}
		}
		using Dynamic::Rect;
		const Rect monitor{ -1920, -100, 0, 980 };
		Check(Dynamic::SampleGeometry(monitor, {-1920,932,0,980})->rect == Rect{-1920,926,0,930}, "bottom gap physical");
		Check(Dynamic::SampleGeometry(monitor, {-1920,-100,-1872,980})->rect == Rect{-1870,-100,-1866,980}, "left negative coordinates");
		Check(Dynamic::SampleGeometry(monitor, {-48,-100,0,980})->rect == Rect{-54,-100,-50,980}, "right negative coordinates");
		Check(!Dynamic::SampleGeometry(monitor, {-1920,-100,0,-52}), "top unsupported");
		Check(!Dynamic::SampleGeometry({0,0,4,4}, {0,0,4,4}), "no adjacent space");
		Check(!Dynamic::SampleGeometry(monitor, {-1921,-100,-1872,980}), "out of monitor rejected");
		Dynamic::Stability state;
		const Dynamic::Segment candidate{blue,0,100};
		Check(!state.Observe(candidate, 1000, 0), "first candidate held");
		Check(!state.Observe(candidate, 1000, 199), "confirmation interval enforced");
		Check(state.Observe(candidate, 1000, 200) && state.color == blue, "confirmed color");
		Check(!state.Observe(candidate, 1000, 700), "identical color not reapplied");
		Check(!state.Observe(Dynamic::Segment{red,0,2}, 1000, 1200) && state.color == blue, "noise keeps valid color");
		Check(!state.Observe(std::nullopt, 1000, 1700) && state.color == blue, "capture failure keeps valid color");
		Dynamic::Burst burst;
		Check(burst.remaining == 0 && burst.due == 0, "event scheduler starts idle");
		burst.Request(1000);
		Check(burst.remaining == 3 && burst.due == 1200, "event arms delayed capture");
		burst.Request(1100);
		Check(burst.remaining == 3 && burst.due == 1200, "event storm cannot extend active burst");
		burst.Consumed(1200);
		Check(burst.remaining == 2 && burst.due == 1500, "second read confirms color");
		burst.Consumed(1500); burst.Consumed(2000);
		Check(burst.remaining == 0 && burst.due == 0, "burst ends without periodic work");
		Check(burst.Request(2001) && burst.due == 3000, "content event during cooldown is delayed rather than lost");
		Check(burst.Request(2100, true), "real window switch overrides cooldown");
		burst.Consumed(2300);
		Check(!burst.Request(2350) && burst.remaining == 2, "noise cannot replenish consumed reads");
		burst.Cancel();
		const Dynamic::Segment closeColor{Rgb{0,0,241},0,100};
		Check(!state.Observe(closeColor,1000,2000), "one-channel exact change awaits confirmation");
		Check(state.Observe(closeColor,1000,2200) && state.color == closeColor.color, "same bucket RGB change is preserved exactly");
		for (bool vertical : {false,true}) {
			const auto exact = Dynamic::Analyze(Image({Rgb{4,5,6},Rgb{7,6,5},Rgb{6,7,4}},vertical).View());
			Check(exact && exact->color == Rgb{7,6,5}, "segment midpoint is an actual source pixel");
		}
		Dynamic::Transition fade;
		fade.Snap(red); fade.Start(blue,1000);
		Check(fade.active && fade.At(1000) == red, "fade starts at displayed color");
		Check(fade.At(1120) == Rgb{120,0,120}, "smooth fade midpoint");
		fade.Start(green,1120);
		Check(fade.At(1120) == Rgb{120,0,120}, "new destination starts from current transition");
		Check(fade.Step(1360) == green && !fade.active, "fade ends at exact target and becomes idle");
		fade.Start(green,1500);
		Check(!fade.active, "identical target creates no animation");
		burst.Request(3000); burst.Cancel();
		Check(burst.remaining == 0 && burst.due == 0, "deactivation cancels all pending work");
		Check(ScopedAppearanceAccent(AppearanceAccent::DynamicV2, false) == AppearanceAccent::Opaque,
			"v2 cannot activate outside maximized state");
		Check(ScopedAppearanceAccent(AppearanceAccent::DynamicV2, true) == AppearanceAccent::DynamicV2,
			"v2 retained in maximized state");
		std::cout << checks << " Dynamic checks passed\n";
		return EXIT_SUCCESS;
	} catch (const std::exception &e) { std::cerr << e.what() << '\n'; return EXIT_FAILURE; }
}
