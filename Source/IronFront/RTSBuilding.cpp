#include "RTSBuilding.h"
#include "UObject/ConstructorHelpers.h"

ARTSBuilding::ARTSBuilding()
{
	Radius = 200.f;
	MaxHealth = 1500.f;

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (Cube.Succeeded())
	{
		Mesh->SetStaticMesh(Cube.Object);
	}
	Mesh->SetWorldScale3D(FVector(4.f, 4.f, 2.f));
}
