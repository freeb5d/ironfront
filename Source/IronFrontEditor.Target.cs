using UnrealBuildTool;

public class IronFrontEditorTarget : TargetRules
{
	public IronFrontEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_4;
		ExtraModuleNames.Add("IronFront");
	}
}
