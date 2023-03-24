FROM mcr.microsoft.com/dotnet/sdk:6.0 AS publish
WORKDIR /mapservices
COPY . .
WORKDIR /mapservices/src/MagicAirPro/Tion.Map.MagicAirPro.WebApi
RUN dotnet publish "Tion.Map.MagicAirPro.WebApi.csproj" -c Release -r debian.10-x64 -o /out

FROM mcr.microsoft.com/dotnet/runtime:6.0
WORKDIR /app
RUN apt-get update					# MAPP-426 For ClosedXML - xlsx export
RUN apt-get install -y libgdiplus   # MAPP-426 For ClosedXML - xlsx export
COPY --from=publish /out .
EXPOSE 80
ENTRYPOINT ["dotnet", "Tion.Map.MagicAirPro.WebApi.dll"]