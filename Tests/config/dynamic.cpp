#include <gtest/gtest.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>
#include "config/taskbarappearance.hpp"
#include "config/activeinactivetaskbarappearance.hpp"

// Keep activation factories within a single COM lifetime, like the application.
class DynamicAppearance : public ::testing::Test {
protected:
    static void SetUpTestSuite() { winrt::init_apartment(winrt::apartment_type::multi_threaded); }
    static void TearDownTestSuite()
    {
        winrt::clear_factory_cache();
        winrt::uninit_apartment();
    }
};

TEST_F(DynamicAppearance, JsonAndWinrtRoundTrip)
{
	rj::GenericDocument<rj::UTF16LE<>> document;
	document.Parse(L"{\"accent\":\"dynamic\",\"color\":\"#123456FF\"}");
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance appearance;
	appearance.Deserialize(document, nullptr);
	EXPECT_EQ(appearance.Accent, AppearanceAccent::Dynamic);
	const txmp::TaskbarAppearance model = appearance;
	EXPECT_EQ(model.Accent(), txmp::AccentState::Dynamic);
	EXPECT_EQ(TaskbarAppearance(model).Accent, AppearanceAccent::Dynamic);
	rj::GenericStringBuffer<rj::UTF16LE<>> buffer;
	rj::Writer<decltype(buffer), rj::UTF16LE<>, rj::UTF16LE<>> writer(buffer);
	writer.StartObject(); appearance.Serialize(writer); writer.EndObject();
	document.Parse(buffer.GetString());
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance restored;
	restored.Deserialize(document, nullptr);
	EXPECT_EQ(restored.Accent, AppearanceAccent::Dynamic);
	EXPECT_EQ(restored.Color.ToRGBA(), appearance.Color.ToRGBA());
}

TEST_F(DynamicAppearance, LegacyAndInactiveRules)
{
	rj::GenericDocument<rj::UTF16LE<>> document;
	document.Parse(L"{\"accent\":\"clear\",\"inactive\":{\"accent\":\"dynamic\"}}");
	ActiveInactiveTaskbarAppearance rule;
	rule.Deserialize(document, nullptr);
	EXPECT_EQ(rule.Accent, AppearanceAccent::Clear);
	ASSERT_TRUE(rule.Inactive);
	EXPECT_EQ(rule.Inactive->Accent, AppearanceAccent::Dynamic);
}

TEST_F(DynamicAppearance, V2JsonAndWinrtRoundTrip)
{
	rj::GenericDocument<rj::UTF16LE<>> document;
	document.Parse(L"{\"accent\":\"dynamic_v2\",\"color\":\"#203040FF\"}");
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance appearance;
	appearance.Deserialize(document, nullptr);
	EXPECT_EQ(appearance.Accent, AppearanceAccent::DynamicV2);
	const txmp::TaskbarAppearance model = appearance;
	EXPECT_EQ(model.Accent(), txmp::AccentState::DynamicV2);
	EXPECT_EQ(TaskbarAppearance(model).Accent, AppearanceAccent::DynamicV2);
	rj::GenericStringBuffer<rj::UTF16LE<>> buffer;
	rj::Writer<decltype(buffer), rj::UTF16LE<>, rj::UTF16LE<>> writer(buffer);
	writer.StartObject(); appearance.Serialize(writer); writer.EndObject();
	document.Parse(buffer.GetString());
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance restored;
	restored.Deserialize(document, nullptr);
	EXPECT_EQ(restored.Accent, AppearanceAccent::DynamicV2);
}
