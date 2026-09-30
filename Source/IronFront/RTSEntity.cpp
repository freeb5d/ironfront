#include "RTSEntity.h"
#include "DrawDebugHelpers.h"
#include "UObject/ConstructorHelpers.h"

ARTSEntity::ARTSEntity()
{
	PrimaryActorTick.bCanEverTick = true;

	Mesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
	SetRootComponent(Mesh);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	if (Cylinder.Succeeded())
	{
		Mesh->SetStaticMesh(Cylinder.Object);
	}
}

void ARTSEntity::BeginPlay()
{
	Super::BeginPlay();
	Health = MaxHealth;
	ApplyColor();
}

void ARTSEntity::SetTeam(int32 NewTeam)
{
	Team = NewTeam;
	ApplyColor();
}

void ARTSEntity::ApplyColor()
{
	if (!Mid)
	{
		Mid = Mesh->CreateDynamicMaterialInstance(0);
	}
	if (Mid)
	{
		Mid->SetVectorParameterValue(TEXT("Color"), Team == 0 ? FLinearColor(0.1f, 0.35f, 1.f) : FLinearColor(1.f, 0.15f, 0.1f));
	}
}

void ARTSEntity::ReceiveHit(float Amount)
{
	Health -= Amount;
	if (Health <= 0.f)
	{
		Destroy();
	}
}

void ARTSEntity::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	const FVector Base = GetActorLocation() * FVector(1, 1, 0) + FVector(0, 0, 5);
	if (bSelected)
	{
		DrawDebugCircle(GetWorld(), Base, Radius + 20.f, 24, FColor::Green, false, -1.f, 0, 4.f, FVector(1, 0, 0), FVector(0, 1, 0), false);
	}
	if (Health < MaxHealth)
	{
		const FVector Top = GetActorLocation() + FVector(0, 0, Mesh->Bounds.BoxExtent.Z + 40.f);
		const float Half = Radius;
		const float Frac = FMath::Clamp(Health / MaxHealth, 0.f, 1.f);
		DrawDebugLine(GetWorld(), Top - FVector(0, Half, 0), Top + FVector(0, Half, 0), FColor::Red, false, -1.f, 0, 6.f);
		DrawDebugLine(GetWorld(), Top - FVector(0, Half, 0), Top + FVector(0, Half * (2.f * Frac - 1.f), 0), FColor::Green, false, -1.f, 0, 6.f);
	}
}
