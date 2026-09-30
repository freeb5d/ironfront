#include "RTSGameMode.h"
#include "RTSUnit.h"
#include "RTSBuilding.h"
#include "RTSCameraPawn.h"
#include "RTSController.h"
#include "RTSHUD.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/DirectionalLight.h"
#include "Engine/SkyLight.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyLightComponent.h"
#include "TimerManager.h"

ARTSGameMode::ARTSGameMode()
{
	PrimaryActorTick.bCanEverTick = true;
	DefaultPawnClass = ARTSCameraPawn::StaticClass();
	PlayerControllerClass = ARTSController::StaticClass();
	HUDClass = ARTSHUD::StaticClass();
}

void ARTSGameMode::BeginPlay()
{
	Super::BeginPlay();
	BuildWorld();
	GetWorldTimerManager().SetTimer(WaveTimer, this, &ARTSGameMode::EnemyWave, 25.f, true, 20.f);
}

void ARTSGameMode::BuildWorld()
{
	UWorld* World = GetWorld();

	// Ground
	AStaticMeshActor* Ground = World->SpawnActor<AStaticMeshActor>(FVector(3500.f, 0.f, 0.f), FRotator::ZeroRotator);
	UStaticMeshComponent* GC = Ground->GetStaticMeshComponent();
	GC->SetMobility(EComponentMobility::Movable);
	GC->SetStaticMesh(LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Plane.Plane")));
	Ground->SetActorScale3D(FVector(120.f, 120.f, 1.f));
	if (UMaterialInstanceDynamic* M = GC->CreateDynamicMaterialInstance(0))
	{
		M->SetVectorParameterValue(TEXT("Color"), FLinearColor(0.08f, 0.2f, 0.08f));
	}

	// Light
	ADirectionalLight* Sun = World->SpawnActor<ADirectionalLight>(FVector::ZeroVector, FRotator(-50.f, 30.f, 0.f));
	Sun->GetLightComponent()->SetMobility(EComponentMobility::Movable);
	Sun->GetLightComponent()->SetIntensity(8.f);
	ASkyLight* Sky = World->SpawnActor<ASkyLight>(FVector(0.f, 0.f, 500.f), FRotator::ZeroRotator);
	Sky->GetLightComponent()->SetMobility(EComponentMobility::Movable);
	Sky->GetLightComponent()->SetIntensity(1.f);
	Sky->GetLightComponent()->RecaptureSky();

	// Bases
	const FVector BasePos[2] = { FVector(0.f, 0.f, 100.f), FVector(7000.f, 0.f, 100.f) };
	for (int32 T = 0; T < 2; ++T)
	{
		ARTSBuilding* B = World->SpawnActor<ARTSBuilding>(BasePos[T], FRotator::ZeroRotator);
		B->SetTeam(T);
		HQ[T] = B;
	}
	for (int32 i = 0; i < 5; ++i)
	{
		SpawnUnit(0);
	}
}

ARTSUnit* ARTSGameMode::SpawnUnit(int32 Team)
{
	if (!HQ[Team].IsValid())
	{
		return nullptr;
	}
	const float Dir = Team == 0 ? 1.f : -1.f;
	const FVector Loc = HQ[Team]->GetActorLocation() + FVector(Dir * 420.f, FMath::FRandRange(-350.f, 350.f), 0.f);
	ARTSUnit* U = GetWorld()->SpawnActor<ARTSUnit>(FVector(Loc.X, Loc.Y, 50.f), FRotator::ZeroRotator);
	if (U)
	{
		U->SetTeam(Team);
	}
	return U;
}

bool ARTSGameMode::TryTrain(int32 Team)
{
	if (Money[Team] < UnitCost || !Status.IsEmpty())
	{
		return false;
	}
	Money[Team] -= UnitCost;
	return SpawnUnit(Team) != nullptr;
}

void ARTSGameMode::EnemyWave()
{
	if (!HQ[0].IsValid() || !HQ[1].IsValid())
	{
		return;
	}
	++WaveCount;
	for (int32 i = 0; i < 2 + WaveCount; ++i)
	{
		if (ARTSUnit* U = SpawnUnit(1))
		{
			U->OrderAttackMove(HQ[0]->GetActorLocation());
		}
	}
}

void ARTSGameMode::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	if (Status.IsEmpty())
	{
		Money[0] += 10.f * DeltaTime;
		if (!HQ[0].IsValid())
		{
			Status = TEXT("DEFEAT");
		}
		else if (!HQ[1].IsValid())
		{
			Status = TEXT("VICTORY");
		}
	}
}
