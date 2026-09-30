#include "RTSCameraPawn.h"

ARTSCameraPawn::ARTSCameraPawn()
{
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));

	Arm = CreateDefaultSubobject<USpringArmComponent>(TEXT("Arm"));
	Arm->SetupAttachment(RootComponent);
	Arm->SetRelativeRotation(FRotator(-60.f, 0.f, 0.f));
	Arm->TargetArmLength = 2500.f;
	Arm->bDoCollisionTest = false;

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(Arm);
}
