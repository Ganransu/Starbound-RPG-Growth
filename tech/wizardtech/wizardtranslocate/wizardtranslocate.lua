require "/scripts/keybinds.lua"

function init()
  self.dashCooldownTimer = 0
  self.rechargeEffectTimer = 0

  self.cost = config.getParameter("cost")
  self.dashMaxDistance = config.getParameter("dashDistance")
  self.dashCooldown = config.getParameter("dashCooldown")
  sb.logInfo("ConfigCooldown: " .. tostring(self.dashCooldown))
  self.rechargeDirectives = config.getParameter("rechargeDirectives", "?fade=B880FCFF=0.25")
  self.rechargeEffectTime = config.getParameter("rechargeEffectTime", 0.1)

  Bind.create("g", translocate)
end

function translocate()
  --sb.logInfo("Cooldown: " .. tostring(self.dashCooldownTimer))
  local isValidWorld = world.terrestrial() or world.type() == "outpost" or world.type() == "scienceoutpost" or world.type() == "unknown"
  if self.dashCooldownTimer == 0 and not status.statPositive("activeMovementAbilities") and isValidWorld and status.resource("energy") > 0 then--status.overConsumeResource("energy", self.cost) then
    local agility = world.entityCurrency(entity.id(),"agilitypoint") or 1
    local distance = world.magnitude(tech.aimPosition(), mcontroller.position())
    local costPercent = -(distance-agility*2.0+20.0)/100.0
    status.modifyResourcePercentage("energy", costPercent)
    local projectileId = world.spawnProjectile(
        "invtransdisc",
        tech.aimPosition(),
        entity.id(),
        {0,0},
        false
      )
    --sb.logInfo("projectile created: " .. tostring(projectileId)) 
    if projectileId then
      world.callScriptedEntity(projectileId, "setOwnerId", entity.id())
      status.setStatusProperty("translocatorDiscId", projectileId)
      status.addEphemeralEffect("translocate")
      self.dashCooldownTimer = self.dashCooldown
    end
  end
end

function uninit()
  tech.setParentDirectives()
end

function update(args)
  if self.dashCooldownTimer > 0 then
    self.dashCooldownTimer = math.max(0, self.dashCooldownTimer - args.dt)
    if self.dashCooldownTimer == 0 then
      self.rechargeEffectTimer = self.rechargeEffectTime
      tech.setParentDirectives(self.rechargeDirectives)
      animator.playSound("recharge")
    end
  end

  if self.rechargeEffectTimer > 0 then
    self.rechargeEffectTimer = math.max(0, self.rechargeEffectTimer - args.dt)
    if self.rechargeEffectTimer == 0 then
      tech.setParentDirectives()
    end
  end
end
