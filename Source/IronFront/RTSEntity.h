#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Components/StaticMeshComponent.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "RTSEntity.generated.h"

/** Base for anything that belongs to a team and can be shot: units and buildings. */
UCLASS(Abstract)
class IRONFRONT_API ARTSEntity : public AActor
{
	GENERATED_BODY()

public:
	ARTSEntity();

	UPROPERTY(VisibleAnywhere)
	TObjectPtr<UStaticMeshComponent> Mesh;

	UPROPERTY(EditAnywhere)
	int32 Team = 0;

	UPROPERTY(EditAnywhere)
	float MaxHealth = 100.f;

	UPROPERTY(VisibleAnywhere)
	float Health = 100.f;

	/** Ground-plane radius, used for range checks and the selection ring. */
	UPROPERTY(EditAnywhere)
	float Radius = 40.f;

	bool bSelected = false;

	void SetTeam(int32 NewTeam);
	void ReceiveHit(float Amount);
	bool IsAlive() const { return Health > 0.f; }

protected:
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaTime) override;

private:
	UPROPERTY()
	TObjectPtr<UMaterialInstanceDynamic> Mid;

	void ApplyColor();
};
