#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "RTSController.generated.h"

class ARTSUnit;

UCLASS()
class IRONFRONT_API ARTSController : public APlayerController
{
	GENERATED_BODY()

public:
	bool bDragging = false;
	FVector2D DragStart = FVector2D::ZeroVector;

protected:
	virtual void BeginPlay() override;
	virtual void PlayerTick(float DeltaTime) override;

private:
	TArray<TWeakObjectPtr<ARTSUnit>> Selected;

	void ClearSelection();
	void BoxSelect(FVector2D A, FVector2D B);
	void ClickSelect();
	void IssueOrder();
	void UpdateCamera(float DeltaTime);
};
