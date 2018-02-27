require "/tech/distortionsphere/distortionsphere.lua"
require "/scripts/rect.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/keybinds.lua"

function init()
  initCommonParameters()

  self.ignorePlatforms = config.getParameter("ignorePlatforms")
  self.damageDisableTime = config.getParameter("damageDisableTime")
  self.damageDisableTimer = 0

  self.headingAngle = nil

  self.normalCollisionSet = {"Block", "Dynamic"}
  if self.ignorePlatforms then
    self.platformCollisionSet = self.normalCollisionSet
  else
    self.platformCollisionSet = {"Block", "Dynamic", "Platform"}
  end

  self.zoneCostPerSec = config.getParameter("zoneCostPerSec")
  self.hoverCost = config.getParameter("energyUsagePerSecond")
  self.healingRate = config.getParameter("healingRate")/100
  self.enableZone = false
  Bind.create("primaryFire", 
    function()
      self.enableZone = true
    end,
	true
  )

  self.damageListener = damageListener("damageTaken", 
    function(notifications)
      for _, notification in pairs(notifications) do
        if notification.healthLost > 0 and notification.sourceEntityId ~= entity.id() then
          damaged()
          return
        end
      end
    end
  )

end


function update(args)
  restoreStoredPosition()

  if not self.specialLast and args.moves["special1"] then
    attemptActivation()
  end
  self.specialLast = args.moves["special1"]

  if not args.moves["special1"] then
    self.forceTimer = nil
  end

  self.damageDisableTimer = math.max(0, self.damageDisableTimer - args.dt)

  self.damageListener:update()

  if self.active then

    -- Gravity Sphere Stat Effects --
    if self.enableZone and status.overConsumeResource("energy", self.zoneCostPerSec * args.dt) then
      activateZone()
    else
      deactivateZone()
    end
	self.enableZone = false
    
    if status.resource("health") ~= 0 then
      animator.setParticleEmitterOffsetRegion("healing", mcontroller.boundBox())
      animator.setParticleEmitterActive("healing", true)
      status.modifyResourcePercentage("health", self.healingRate * args.dt)
    end
    status.addEphemeralEffect("wizardlowgrav", math.huge)
    

    local groundDirection
    if self.damageDisableTimer == 0 then
      groundDirection = findGroundDirection()
    end

    if groundDirection then
      if not self.headingAngle then
        self.headingAngle = (math.atan(groundDirection[2], groundDirection[1]) + math.pi / 2) % (math.pi * 2)
      end

      local moveX = 0
      if args.moves["right"] then moveX = moveX + 1 end
      if args.moves["left"] then moveX = moveX - 1 end
      if moveX ~= 0 then
        -- find any collisions in the moving direction, and adjust heading angle *up* until there is no collision
        -- this makes the heading direction follow concave corners
        local adjustment = 0
        for a = 0, math.pi, math.pi / 4 do
          local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
          adjustment = moveX * a
          if not world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
            break
          end
        end
        self.headingAngle = self.headingAngle + adjustment

        -- find empty space in the moving direction and adjust heading angle *down* until it collides
        -- adjust to the angle *before* the collision occurs
        -- this makes the heading direction follow convex corners
        adjustment = 0
        for a = 0, -math.pi, -math.pi / 4 do
          local testPos = vec2.add(mcontroller.position(), vec2.rotate({moveX * 0.25, 0}, self.headingAngle + (moveX * a)))
          if world.polyCollision(poly.translate(poly.scale(mcontroller.collisionPoly(), 1.0), testPos), nil, self.normalCollisionSet) then
            break
          end
          adjustment = moveX * a
        end
        self.headingAngle = self.headingAngle + adjustment

        -- apply a gravitation like force in the ground direction, while moving in the controlled direction
        -- Note: this ground force causes weird collision when moving up slopes, result is you move faster up slopes
        local groundAngle = self.headingAngle - (math.pi / 2)
        mcontroller.controlApproachVelocity(vec2.withAngle(groundAngle, self.ballSpeed), 300)

        local moveDirection = vec2.rotate({moveX, 0}, self.headingAngle)
        mcontroller.controlApproachVelocityAlongAngle(math.atan(moveDirection[2], moveDirection[1]), self.ballSpeed, 2000)

        self.angularVelocity = -moveX * self.ballSpeed
      else
        mcontroller.controlApproachVelocity({0,0}, 2000)
        self.angularVelocity = 0
      end

      mcontroller.controlDown()
      updateAngularVelocity(args.dt)

      self.transformedMovementParameters.gravityEnabled = false
    else
      updateAngularVelocity(args.dt)
      self.transformedMovementParameters.gravityEnabled = true
    end

    mcontroller.controlParameters(self.transformedMovementParameters)
    status.setResourcePercentage("energyRegenBlock", 1.0)
  
    updateRotationFrame(args.dt)

    checkForceDeactivate(args.dt)
  else
    self.headingAngle = nil
     -- DisableEffects --
    deactivateZone()
    status.removeEphemeralEffect("wizardlowgrav")
    animator.setParticleEmitterActive("healing", false)
  end
 
  updateTransformFade(args.dt)

  self.lastPosition = mcontroller.position()

  if status.statPositive("ivrpguchoversphere") and self.active and args.moves["jump"] and status.overConsumeResource("energy", self.hoverCost * args.dt) then
    hover(args)
    self.hovering = true
  else
    animator.setAnimationState("hover", "off")
    self.hovering = false
  end

end

function activateZone()
    if not self.pushzone then
      self.pushzone = world.spawnProjectile("wizardpushzone",
                                            mcontroller.position(),
                                            entity.id(),
                                            {0,0},
                                            true,
                                            {}
                                           )
    end
end

function deactivateZone()
    if self.pushzone then
      world.entityQuery(mcontroller.position(),1,
        {
         withoutEntityId = entity.id(),
         includedTypes = {"projectile"},
         callScript = "removeZone",
         callScriptArgs = {self.pushzone}
        }
      )
      self.pushzone = nil
    end
end

function damaged()
  if self.active then
    self.damageDisableTimer = self.damageDisableTime
  end
end

function findGroundDirection()
  for i = 0, 3 do
    local angle = (i * math.pi / 2) - math.pi / 2
    local collisionSet = i == 1 and self.platformCollisionSet or self.normalCollisionSet
    local testPos = vec2.add(mcontroller.position(), vec2.withAngle(angle, 0.25))
    if world.polyCollision(poly.translate(mcontroller.collisionPoly(), testPos), nil, collisionSet) then
      return vec2.withAngle(angle, 1.0)
    end
  end
end

function hover(args)
  animator.setAnimationState("hover", "on")
  local agility = world.entityCurrency(entity.id(),"agilitypoint") or 1
  local maxSpeed = agility^2 / 180.0 + 25
  local velocity = world.distance(tech.aimPosition(), mcontroller.position())
  --local direction = mcontroller.facingDirection()
  velocity = vec2.mag(velocity) > maxSpeed and vec2.withAngle(vec2.angle(velocity), maxSpeed) or velocity
  velocity = {velocity[1],velocity[2] / 1.5}
  local hoverControlForce = config.getParameter("hoverControlForce")
  mcontroller.controlApproachVelocity(velocity, hoverControlForce)
  self.angularVelocity = -mcontroller.xVelocity()/2
end
