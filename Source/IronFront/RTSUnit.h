#pragma once

#include "CoreMinimal.h"
#include "RTSEntity.h"
#include "RTSUnit.generated.h"

UCLASS()
class IRONFRONT_API ARTSUnit : public ARTSEntity
{
	GENERATED_BODY()

public:
	ARTSUnit();

	UPROPERTY(EditAnywhere) float Speed = 450.f;
	UPROPERTY(EditAnywhere) float Range = 450.f;
	UPROPERTY(EditAnywhere) float Damage = 12.f;
	UPROPERTY(EditAnywhere) float Cooldown = 1.f;
	UPROPERTY(EditAnywhere) float Sight = 1500.f;

	/** Player order: walk there, ignore enemies on the way. */
	void OrderMove(const FVector& Dest);
	/** Player order: chase and kill this entity. */
	void OrderAttack(ARTSEntity* Enemy);
	/** AI order: walk there, engaging anything met on the way. */
	void OrderAttackMove(const FVector& Dest);

protected:
	virtual void Tick(float DeltaTime) override;

private:
	TWeakObjectPtr<ARTSEntity> Target;
	FVector Goal = FVector::ZeroVector;
	bool bHasGoal = false;
	bool bAttackMove = false;
	float AcquireTimer = 0.f;
	float CooldownLeft = 0.f;

	ARTSEntity* FindEnemy() const;
	void MoveToward(const FVector& Point, float DeltaTime);
};
