#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "RTSGameMode.generated.h"

class ARTSUnit;
class ARTSBuilding;

UCLASS()
class IRONFRONT_API ARTSGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	ARTSGameMode();

	static constexpr float UnitCost = 100.f;

	float Money[2] = { 300.f, 0.f };
	FString Status;

	ARTSUnit* SpawnUnit(int32 Team);
	bool TryTrain(int32 Team);

protected:
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaTime) override;

private:
	TWeakObjectPtr<ARTSBuilding> HQ[2];
	FTimerHandle WaveTimer;
	int32 WaveCount = 0;

	void BuildWorld();
	void EnemyWave();
};
